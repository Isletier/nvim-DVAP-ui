local function get_default_threadline_hl()
    vim.api.nvim_set_hl(0, "dvap_CursorLine", { bg = '#19435b' })
    return "dvap_CursorLine"
end

local default_config = {
    default_host = "127.0.0.1",
    default_port = 9000,
    debug_cursorline_hl = get_default_threadline_hl(),
    breakpoint_unconditional_sign = "DVAP_breakpoint_unconditional",
    breakpoint_conditional_sign = "DVAP_breakpoint_conditional",
    set_default_keymaps = true,
    threadline_hl = "Search"
}

local M = {
    core = nil,

    thread_buf_cache = {},
    thread_watch_num = {},
    thread_watch_pos_cache = { "", 0 },

    cursor_line_opt_cache = nil,
    cursor_line_hl_cache = nil,

    QF_breakpoint_id_cache = nil,

    DVAP_namespace = vim.api.nvim_create_namespace("dvap"),
    DVAP_CursorLine_hl = { bg = '#19435b' },

    config = default_config
}

function M.highlight_current_line(thread_num, file_path, line_number)
    local bufnr = vim.fn.bufadd(file_path)
    vim.fn.bufload(bufnr)

    vim.api.nvim_buf_set_extmark(bufnr, M.DVAP_namespace, line_number - 1, 0, {
        line_hl_group = M.config.threadline_hl,
        hl_mode = "combine",
    })

    M.thread_buf_cache[thread_num] = bufnr
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

    vim.api.nvim_win_set_cursor(0, { tonumber(line_number), 0 })
    M.thread_watch_pos_cache[1] = file_path
    M.thread_watch_pos_cache[2] = line_number
end

function M.try_focus()
    local threads = M.core.get_state().threads

    if M.thread_watch_num ~= nil and threads[M.thread_watch_num] ~= nil then
        M.thread_watch_focus(threads[M.thread_watch_num]["file_path"], threads[M.thread_watch_num]["line"])
        return
    end

    --try tid
    for _, thread in pairs(threads) do
        if thread["tid"] == M.thread_watch_num then
            M.thread_watch_focus(thread["file_path"], thread["line"])
        end
    end

end

function M.render(state)
    local threads = state.threads
    local breakpoints = state.breakpoints

    for _, num in pairs(M.thread_buf_cache) do
        M.clear_previous_highlight(num)
    end

    for num, thread in pairs(threads) do
        M.highlight_current_line(num, thread["file_path"], thread["line"])
    end

    vim.fn.sign_unplace("DVAP_sign_group")
    for _, breakpoint in pairs(breakpoints) do
        local b_sign = nil

        if breakpoint.nonconditional and breakpoint.enabled then
            b_sign = M.config.breakpoint_unconditional_sign
        else
            b_sign = M.config.breakpoint_conditional_sign
        end

        local bufnr = vim.fn.bufnr(breakpoint.file_path)
        if bufnr ~= -1 then
            vim.fn.bufload(bufnr)
            vim.fn.sign_place(
                0,
                "DVAP_sign_group",
                b_sign,
                bufnr,
                { lnum = breakpoint.line }
            )
        end
    end

    M.try_focus()
end

function M.start_ui_render()
    M.cursor_line_opt_cache = vim.opt.cursorline
    M.cursor_line_hl_cache = vim.api.nvim_get_hl(0, { name = 'CursorLine' })

    vim.api.nvim_set_hl(0, 'CursorLine', { link = M.config.debug_cursorline_hl })
end

function M.reset_ui()
    local all_buffers = vim.api.nvim_list_bufs()

    for _, bufnr in ipairs(all_buffers) do
        vim.api.nvim_buf_clear_namespace(bufnr, M.DVAP_namespace, 0, -1)
    end

    M.thread_watch_num = nil
    M.thread_watch_pos_cache = { "", 0 }
    M.thread_buf_cache = {}

    assert(M.cursor_line_opt_cache ~= nil and M.cursor_line_hl_cache ~= nil)
    vim.opt.cursorline = M.cursor_line_opt_cache
    vim.api.nvim_set_hl(0, 'CursorLine', M.cursor_line_hl_cache)

    vim.fn.sign_unplace("DVAP_sign_group")
end

function M.connectCMD()
    vim.ui.input({
        prompt = 'Enter DVAP endpoint HOST:PORT: ',
        default = M.config.default_host .. ':' .. M.config.default_port,
    }, function(endpoint)
        local host, port = string.match(endpoint, "([^:]+):(%d+)")

        if not host or not port then
            return nil, "Invalid endpoint format. Use HOST:PORT"
        end

        M.core.connect("/", host, tonumber(port))
    end)
end

function M.set_watch_thread(thread_num)
    M.thread_watch_num = thread_num.fargs[1]
    M.thread_watch_pos_cache = { "", 0 }
end


function M.Reset_watch_thread()
    M.thread_watch_num = nil
    M.thread_watch_pos_cache = { "", 0 }
end


function M.set_breakpoint_qf()
    local breakpoints = M.core.get_state().breakpoints

    local qf_items = {}
    for _, item in pairs(breakpoints) do
        table.insert(qf_items, {
            filename = item.file_path,
            lnum = item.line,
            text = string.format("[%s] Enabled: %s, Cond: %s",
                                 item.type_str, item.enabled, item.nonconditional),
            type = item.type_str:sub(1,1):upper() -- Опционально: первая буква типа (E, W, etc.)
        })
    end

    local qf_id = vim.fn.getqflist({id = 0}).id
    if M.QF_breakpoint_id_cache ~= nil and M.QF_breakpoint_id_cache == qf_id then
        vim.fn.setqflist({}, 'u', { id = qf_id, items = qf_items })
        return
    end

    vim.fn.setqflist({}, ' ', { items = qf_items })
    M.QF_breakpoint_id_cache = vim.fn.getqflist({id = 0}).id
    vim.cmd(":copen")
end

function M.set_thread_qf()
    local threads = M.core.get_state().threads

    local qf_items = {}
    for _, item in pairs(threads) do
        table.insert(qf_items, {
            filename = item.file_path,
            lnum = item.line,
            text = string.format("Tid: %s", item.tid),
        })
    end

    local qf_id = vim.fn.getqflist({id = 0}).id
    if M.QF_breakpoint_id_cache ~= nil and M.QF_breakpoint_id_cache == qf_id then
        vim.fn.setqflist({}, 'u', { id = qf_id, items = qf_items })
        return
    end

    vim.fn.setqflist({}, ' ', { items = qf_items })
    M.QF_breakpoint_id_cache = vim.fn.getqflist({id = 0}).id
    vim.cmd(":copen")
end


-- Function to set up the plugin
function M.setup(config)
    local ok
    ok, M.core = pcall(require, "nvim-dvap")
    if not ok then
        vim.notify("nvim-DVAP core dont found", 4)
        return
    end

    M.config = vim.tbl_deep_extend("force", default_config, config or {})

    M.core.setup({
        on_connected    = M.start_ui_render,
        on_disconnected = M.reset_ui,
        on_state_updated = M.render
    })

    vim.api.nvim_create_user_command(
        'DVAPConnect',
        M.connectCMD,
        {}
    )

    vim.api.nvim_create_user_command(
        'DVAPDisconnect',
        M.core.disconnect,
        {}
    )

    vim.api.nvim_create_user_command(
        'DVAPWatch',
        M.set_watch_thread,
        { nargs = 1 }
    )

    vim.api.nvim_create_user_command(
        'DVAPFocus',
        M.try_focus,
        {}
    )

    vim.api.nvim_create_user_command(
        'DVAPResetWatch',
        M.Reset_watch_thread,
        {}
    )

    vim.api.nvim_create_user_command(
        'DVAPBreakpointList',
        M.set_breakpoint_qf,
        {}
    )

    vim.api.nvim_create_user_command(
        'DVAPThreadList',
        M.set_thread_qf,
        {}
    )

    if M.config.set_default_keymaps then
        vim.keymap.set("n", "<leader>dc",  "<cmd>DVAPConnect<CR>")
        vim.keymap.set("n", "<leader>dd",  "<cmd>DVAPDisconnect<CR>")
        vim.keymap.set("n", "<leader>dw",  ":DVAPWatch ")
        vim.keymap.set("n", "<leader>df",  "<cmd>DVAPFocus<CR>")
        vim.keymap.set("n", "<leader>dr",  "<cmd>DVAPResetWatch<CR>")

        vim.keymap.set("n", "<leader>dqb", "<cmd>DVAPBreakpointList<CR>")
        vim.keymap.set("n", "<leader>dqt", "<cmd>DVAPThreadList<CR>")
    end

    vim.fn.sign_define("DVAP_breakpoint_unconditional", { text = "B", texthl = "Character" })
    vim.fn.sign_define("DVAP_breakpoint_conditional",   { text = "C", texthl = "Character" })
end

-- Return the module
return M

