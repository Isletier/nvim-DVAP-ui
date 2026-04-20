local function setup_default_highlights()
    vim.api.nvim_set_hl(0, "dvap_CursorLine",       { bg = '#1c455a',                   default = true })
    vim.api.nvim_set_hl(0, "dvap_FollowCursorLine", { bg = '#163546',                   default = true })
    vim.api.nvim_set_hl(0, "dvap_SelectedThread",   { bg = '#474728',                   default = true })
    vim.api.nvim_set_hl(0, "dvap_ThreadLine",       { bg = '#4e3112',                   default = true })
    vim.api.nvim_set_hl(0, "dvap_LostThread",       { bg = '#313d4d', fg = '#888888',   default = true })
end

setup_default_highlights()

local default_config = {
    default_host = "127.0.0.1",
    default_port = 56789,

    set_default_keymaps = true,
    virt_text_thread_info = true,

    follow_mode    = true,
    default_reconnect_interval = 500,
}

local M = {
    ---@type DvapModule?
    core = nil,

    thread_buf_cache        = {},
    thread_watch_pos_cache  = { "", 0 },
    thread_follow_selected  = false,

    cursor_line_opt_cache   = nil,
    cursor_line_hl_cache    = nil,

    QF_breakpoint_id_cache = nil,
    QF_thread_id_cache     = nil,

    DVAP_namespace = vim.api.nvim_create_namespace("dvap"),

    config = default_config
}

function M.update_cursorline_hl()
    local hl = M.thread_follow_selected and "dvap_FollowCursorLine" or "dvap_CursorLine"
    vim.api.nvim_set_hl(0, 'CursorLine', { link = hl })
end

function M.highlight_current_line(thread_id, thread, is_selected)
    local bufnr = vim.fn.bufadd(thread.file_path)
    vim.fn.bufload(bufnr)

    local hl_group
    if thread.lost then
        hl_group = "dvap_LostThread"
    elseif is_selected then
        hl_group = "dvap_SelectedThread"
    else
        hl_group = "dvap_ThreadLine"
    end

    local virt_text = nil
    if M.config.virt_text_thread_info then
        local label = string.format(" [%s tid:%s%s%s]",
            thread_id,
            thread.tid,
            is_selected and " ◀selected" or "",
            thread.lost  and " ⚠lost"     or "")
        virt_text = { { label, "Comment" } }
    end

    local ok, _ = pcall(vim.api.nvim_buf_set_extmark, bufnr, M.DVAP_namespace, thread.line - 1, 0, {
        line_hl_group = hl_group,
        hl_mode       = "combine",
        virt_text     = virt_text,
        virt_text_pos = "eol",
        priority      = is_selected and 300 or 100,
    })

    if not ok then
        print("Warn: failed to find thread file location")
        return
    end

    M.thread_buf_cache[thread_id] = bufnr
end

function M.clear_previous_highlight(bufnr)
    if bufnr ~= nil then
        vim.api.nvim_buf_clear_namespace(bufnr, M.DVAP_namespace, 0, -1)
    end
end

function M.thread_watch_focus(file_path, line_number)
    if M.thread_watch_pos_cache[1] == file_path and M.thread_watch_pos_cache[2] == line_number then
        return
    end

    local bufnr = vim.fn.bufadd(file_path)
    vim.fn.bufload(bufnr)

    vim.api.nvim_set_current_buf(bufnr)
    local ok, _ = pcall(vim.api.nvim_win_set_cursor, 0, { tonumber(line_number), 0 })
    if not ok then
        print("Warn: failed to set cursor to path:line")
    end

    M.thread_watch_pos_cache[1] = file_path
    M.thread_watch_pos_cache[2] = line_number
end

function M.try_focus()
    local state = M.core.get_state()

    if state.selected == nil then
        return
    end

    local threads = state.threads

    if threads[state.selected] ~= nil then
        M.thread_watch_focus(threads[state.selected]["file_path"], threads[state.selected]["line"])
    end
end

function M.render(state)
    local threads    = state.threads
    local breakpoints = state.breakpoints

    for _, bufnr in pairs(M.thread_buf_cache) do
        M.clear_previous_highlight(bufnr)
    end
    M.thread_buf_cache = {}

    for id, thread in pairs(threads) do
        M.highlight_current_line(id, thread, id == state.selected)
    end

    vim.fn.sign_unplace("DVAP_sign_group")
    for _, breakpoint in pairs(breakpoints) do
        local b_sign = (breakpoint.nonconditional and breakpoint.enabled)
            and "DVAP_breakpoint_unconditional"
            or  "DVAP_breakpoint_conditional"

        local bufnr = vim.fn.bufnr(breakpoint.file_path)
        if bufnr ~= -1 then
            vim.fn.bufload(bufnr)
            vim.fn.sign_place(0, "DVAP_sign_group", b_sign, bufnr, { lnum = breakpoint.line })
        end
    end

    if M.thread_follow_selected then
        M.try_focus()
    end
end

function M.start_ui_render()
    M.cursor_line_opt_cache = vim.opt.cursorline
    M.cursor_line_hl_cache  = vim.api.nvim_get_hl(0, { name = 'CursorLine' })
    M.thread_follow_selected = M.config.follow_mode
    M.update_cursorline_hl()
end

function M.reset_ui()
    local all_buffers = vim.api.nvim_list_bufs()
    for _, bufnr in ipairs(all_buffers) do
        vim.api.nvim_buf_clear_namespace(bufnr, M.DVAP_namespace, 0, -1)
    end

    M.thread_watch_pos_cache = { "", 0 }
    M.thread_buf_cache       = {}

    vim.opt.cursorline = M.cursor_line_opt_cache
    if M.cursor_line_hl_cache then
        ---@diagnostic disable-next-line: param-type-mismatch
        vim.api.nvim_set_hl(0, 'CursorLine', M.cursor_line_hl_cache)
    end

    vim.fn.sign_unplace("DVAP_sign_group")
end

function M.connectCMD()
    local default_input = string.format("%s:%d/events %d",
        M.config.default_host,
        M.config.default_port,
        M.config.default_reconnect_interval)

    vim.ui.input({
        prompt  = 'Enter endpoint {host}:{port}/events [retry_interval_ms] ',
        default = default_input,
    }, function(input)
        if not input then
            vim.notify("[DVAP] Error: missing endpoint", vim.log.levels.ERROR)
            return
        end

        local url, rest = input:match("^(%S+)%s*(.-)%s*$")
        if not url then
            vim.notify("[DVAP] Error: missing endpoint", vim.log.levels.ERROR)
            return
        end

        local host, port = url:match("([^:]+):(%d+)/events$")
        if not host or not port then
            vim.notify("[DVAP] Error: endpoint must be 'host:port/events'", vim.log.levels.ERROR)
            return
        end

        local interval = 0
        if rest ~= "" then
            local interv = tonumber(rest)
            if not interv or interv < 0 or interv ~= math.floor(interv) then
                vim.notify("[DVAP] Error: expected a positive integer (ms) after endpoint, got '" .. rest .. "'", vim.log.levels.ERROR)
                return
            end
            interval = interv
        end

        M.core.connect_entry(url, interval)
    end)
end

function M.disconnect_cmd()
    M.core.disconnect_entry()
end

function M.Toggle_follow()
    if not M.core or not M.core.client then
        vim.notify("[DVAP-ui] Debug session is not connected, ignoring", vim.log.levels.INFO)
        return
    end

    M.thread_follow_selected = not M.thread_follow_selected
    M.update_cursorline_hl()
    if M.thread_follow_selected then
        M.force_focus()
    end
end

function M.set_breakpoint_qf()
    local breakpoints = M.core.get_state().breakpoints

    local qf_items = {}
    for _, item in pairs(breakpoints) do
        table.insert(qf_items, {
            filename = item.file_path,
            lnum     = item.line,
            text     = string.format("Enabled: %s, NoCond: %s", item.enabled, item.nonconditional),
        })
    end

    local qf_id = vim.fn.getqflist({ id = 0 }).id
    if M.QF_breakpoint_id_cache ~= nil and M.QF_breakpoint_id_cache == qf_id then
        vim.fn.setqflist({}, 'u', { id = qf_id, items = qf_items })
        return
    end

    vim.fn.setqflist({}, ' ', { items = qf_items })
    M.QF_breakpoint_id_cache = vim.fn.getqflist({ id = 0 }).id
    vim.cmd(":copen")
end

function M.set_thread_qf()
    local state   = M.core.get_state()
    local threads = state.threads

    local qf_items = {}
    local qf_rest  = {}
    for id, item in pairs(threads) do
        local flags = ""
        if id == state.selected then flags = flags .. " [SELECTED]" end
        if item.lost            then flags = flags .. " [LOST]"     end

        local entry = {
            filename = item.file_path,
            lnum     = item.line,
            text     = string.format("%s tid:%s%s", id, item.tid, flags),
        }

        if id == state.selected then
            table.insert(qf_items, entry)
        else
            table.insert(qf_rest, entry)
        end
    end
    vim.list_extend(qf_items, qf_rest)

    local qf_id = vim.fn.getqflist({ id = 0 }).id
    if M.QF_thread_id_cache ~= nil and M.QF_thread_id_cache == qf_id then
        vim.fn.setqflist({}, 'u', { id = qf_id, items = qf_items })
        return
    end

    vim.fn.setqflist({}, ' ', { items = qf_items })
    M.QF_thread_id_cache = vim.fn.getqflist({ id = 0 }).id
    vim.cmd(":copen")
end

local function copy_path_with_line()
    local file = vim.api.nvim_buf_get_name(0)
    if file == "" then return print("Buffer has no file") end

    local line   = vim.api.nvim_win_get_cursor(0)[1]
    local result = string.format("%s:%d", file, line)
    vim.fn.setreg('+', result)
end

function M.force_focus()
    --note: double check in case of toggle follow mode, should be better
    if not M.core or not M.core.client then
        vim.notify("[DVAP-ui] Debug session is not connected, ignoring", vim.log.levels.INFO)
        return
    end

    M.thread_watch_pos_cache = { "", 0 }
    M.try_focus()
end

function M.setup(config)
    local ok
    ok, M.core = pcall(require, "nvim-dvap")
    if not ok then
        vim.notify("nvim-DVAP core not found", vim.log.levels.ERROR)
        return
    end

    M.config = vim.tbl_deep_extend("force", default_config, config or {})

    M.core.setup({
        on_connected       = M.start_ui_render,
        on_disconnected    = M.reset_ui,
        on_state_updated   = M.render,
        reconnect_interval = M.config.default_reconnect_interval,
    })

    vim.api.nvim_create_user_command('DVAPConnect',      M.connectCMD,      {})
    vim.api.nvim_create_user_command('DVAPDisconnect',   M.disconnect_cmd,  {})
    vim.api.nvim_create_user_command('DVAPFocus',        M.force_focus,     {})
    vim.api.nvim_create_user_command('DVAPToggleFollow', M.Toggle_follow,   {})
    vim.api.nvim_create_user_command('DVAPBreakpointList', M.set_breakpoint_qf, {})
    vim.api.nvim_create_user_command('DVAPThreadList',   M.set_thread_qf,   {})
    vim.api.nvim_create_user_command('DVAPGetPathLine',  copy_path_with_line, {})

    if M.config.set_default_keymaps then
        vim.keymap.set("n", "<leader>dc",  "<cmd>DVAPConnect<CR>")
        vim.keymap.set("n", "<leader>dd",  "<cmd>DVAPDisconnect<CR>")
        vim.keymap.set("n", "<leader>dt",  "<cmd>DVAPToggleFollow<CR>")
        vim.keymap.set("n", "<leader>df",  "<cmd>DVAPFocus<CR>")
        vim.keymap.set("n", "<leader>dp",  "<cmd>DVAPGetPathLine<CR>")
        vim.keymap.set("n", "<leader>dqb", "<cmd>DVAPBreakpointList<CR>")
        vim.keymap.set("n", "<leader>dqt", "<cmd>DVAPThreadList<CR>")
    end

    vim.fn.sign_define("DVAP_breakpoint_unconditional", { text = "B", texthl = "Character" })
    vim.fn.sign_define("DVAP_breakpoint_conditional",   { text = "C", texthl = "Character" })
end

return M
