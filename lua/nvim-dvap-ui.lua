--- nvim-dvap-ui
---
--- Visual layer for nvim-DVAP. Subscribes to the core's state callbacks and
--- paints thread positions, breakpoints, and a session-wide CursorLine accent
--- while a debug session is connected. Provides user commands and keymaps for
--- connect/disconnect, follow-mode, and quickfix views of threads/breakpoints.
---
--- Public entry point: require('nvim-dvap-ui').setup(config)

local function setup_default_highlights()
    vim.api.nvim_set_hl(0, "dvap_CursorLine",       { bg = '#1c455a',                   default = true })
    vim.api.nvim_set_hl(0, "dvap_FollowCursorLine", { bg = '#163546',                   default = true })
    vim.api.nvim_set_hl(0, "dvap_SelectedThread",   { bg = '#474728',                   default = true })
    vim.api.nvim_set_hl(0, "dvap_ThreadLine",       { bg = '#4e3112',                   default = true })
    vim.api.nvim_set_hl(0, "dvap_LostThread",       { bg = '#313d4d', fg = '#888888',   default = true })
end

setup_default_highlights()


---@class DvapUIConfig
---@field default_host               string   Initial host in the connect prompt
---@field default_port               integer  Initial port in the connect prompt
---@field reconnect_interval         integer  Default reconnect interval (ms); 0 disables auto-reconnect
---@field follow_mode                boolean  Start the session in follow mode
---@field virt_text_thread_info      boolean  Render thread id/tid as EOL virtual text
---@field set_default_keymaps        boolean  Register the default <leader>d* keymaps

---@type DvapUIConfig
local default_config = {
    default_host          = "127.0.0.1",
    default_port          = 56789,
    reconnect_interval    = 500,
    follow_mode           = true,
    virt_text_thread_info = true,
    set_default_keymaps   = true,
}


---@class DvapUIModule
---@field core                   DvapModule?
---@field config                 DvapUIConfig
---@field thread_buf_cache       table<string, integer>
---@field thread_watch_pos_cache { [1]: string, [2]: integer }
---@field thread_follow_selected boolean
---@field DVAP_namespace         integer
local M = {
    core = nil,

    thread_buf_cache       = {},
    thread_watch_pos_cache = { "", 0 },
    thread_follow_selected = false,

    cursor_line_opt_cache  = nil,
    cursor_line_hl_cache   = nil,

    QF_breakpoint_id_cache = nil,
    QF_thread_id_cache     = nil,

    DVAP_namespace = vim.api.nvim_create_namespace("dvap"),

    config = default_config,
}


--- Links the global CursorLine group to our plugin highlight, chosen based on
--- whether follow mode is active. Acts as a session-wide "debug mode" indicator.
function M.update_cursorline_hl()
    local hl = M.thread_follow_selected and "dvap_FollowCursorLine" or "dvap_CursorLine"
    vim.api.nvim_set_hl(0, 'CursorLine', { link = hl })
end


--- Paints a thread's current execution line via an extmark.
---@param thread_id   string
---@param thread      DvapThread
---@param is_selected boolean
function M.highlight_current_line(thread_id, thread, is_selected)
    local ok_load, bufnr = pcall(function()
        local b = vim.fn.bufadd(thread.file_path)
        vim.fn.bufload(b)
        return b
    end)
    if not ok_load or not bufnr then
        vim.notify("[DVAP-ui] Failed to load buffer for " .. thread.file_path, vim.log.levels.WARN)
        return
    end

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

    local ok = pcall(vim.api.nvim_buf_set_extmark, bufnr, M.DVAP_namespace, thread.line - 1, 0, {
        line_hl_group = hl_group,
        hl_mode       = "combine",
        virt_text     = virt_text,
        virt_text_pos = "eol",
        priority      = is_selected and 300 or 100,
    })
    if not ok then
        vim.notify("[DVAP-ui] Failed to place extmark at " .. thread.file_path .. ":" .. thread.line, vim.log.levels.WARN)
        return
    end

    M.thread_buf_cache[thread_id] = bufnr
end


---@param bufnr integer?
function M.clear_previous_highlight(bufnr)
    if bufnr ~= nil then
        vim.api.nvim_buf_clear_namespace(bufnr, M.DVAP_namespace, 0, -1)
    end
end


--- Brings the selected thread's file:line into the current window, de-duping
--- on a cached (file, line) to avoid redundant buffer switches.
---@param file_path   string
---@param line_number integer
function M.thread_watch_focus(file_path, line_number)
    if M.thread_watch_pos_cache[1] == file_path and M.thread_watch_pos_cache[2] == line_number then
        return
    end

    local ok_load, bufnr = pcall(function()
        local b = vim.fn.bufadd(file_path)
        vim.fn.bufload(b)
        return b
    end)
    if not ok_load or not bufnr then
        vim.notify("[DVAP-ui] Failed to load buffer for " .. file_path, vim.log.levels.WARN)
        return
    end

    vim.api.nvim_set_current_buf(bufnr)
    local ok = pcall(vim.api.nvim_win_set_cursor, 0, { line_number, 0 })
    if not ok then
        vim.notify("[DVAP-ui] Failed to set cursor to " .. file_path .. ":" .. line_number, vim.log.levels.WARN)
        return
    end

    M.thread_watch_pos_cache[1] = file_path
    M.thread_watch_pos_cache[2] = line_number
end


--- Focuses the selected thread's location, if any.
function M.try_focus()
    if not M.core then return end

    local state = M.core.get_state()
    if state.selected == nil then return end

    local thread = state.threads[state.selected]
    if thread ~= nil then
        M.thread_watch_focus(thread.file_path, thread.line)
    end
end


--- Core callback: repaints thread highlights and breakpoint signs from a new state.
---@param state DvapState
function M.render(state)
    for _, bufnr in pairs(M.thread_buf_cache) do
        M.clear_previous_highlight(bufnr)
    end
    M.thread_buf_cache = {}

    for id, thread in pairs(state.threads) do
        M.highlight_current_line(id, thread, id == state.selected)
    end

    vim.fn.sign_unplace("DVAP_sign_group")
    for _, breakpoint in pairs(state.breakpoints) do
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


--- Core callback: captures prior CursorLine state and enters "debug mode".
function M.start_ui_render()
    M.cursor_line_opt_cache  = vim.opt.cursorline
    M.cursor_line_hl_cache   = vim.api.nvim_get_hl(0, { name = 'CursorLine' })
    M.thread_follow_selected = M.config.follow_mode
    M.update_cursorline_hl()
end


--- Core callback: clears all plugin extmarks/signs and restores CursorLine.
function M.reset_ui()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
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


--- Parses the connect prompt: "host:port/events" optionally followed by
--- a non-negative integer (reconnect interval in ms).
---@param  input string
---@return string? url
---@return integer? interval
---@return string?  err
local function parse_connect_input(input)
    local url, rest = input:match("^(%S+)%s*(.-)%s*$")
    if not url or url == "" then
        return nil, nil, "missing endpoint"
    end

    local host, port = url:match("([^:]+):(%d+)/events$")
    if not host or not port then
        return nil, nil, "endpoint must be 'host:port/events'"
    end

    if rest == "" then
        return url, nil, nil
    end

    local interval = tonumber(rest)
    if not interval or interval < 0 or interval ~= math.floor(interval) then
        return nil, nil, "expected a non-negative integer (ms) after endpoint, got '" .. rest .. "'"
    end

    return url, interval, nil
end


function M.connect_cmd()
    if not M.core then
        vim.notify("[DVAP-ui] Core module is not available", vim.log.levels.ERROR)
        return
    end

    local default_input = string.format("%s:%d/events %d",
        M.config.default_host,
        M.config.default_port,
        M.config.reconnect_interval)

    vim.ui.input({
        prompt  = 'Enter endpoint {host}:{port}/events [retry_interval_ms] ',
        default = default_input,
    }, function(input)
        if not input then return end  -- user cancelled

        local url, interval, err = parse_connect_input(input)
        if url == nil or err then
            vim.notify("[DVAP-ui] " .. err, vim.log.levels.ERROR)
            return
        end

        M.core.connect_entry(url, interval or M.config.reconnect_interval)
    end)
end


function M.disconnect_cmd()
    if not M.core then return end
    M.core.disconnect_entry()
end


--- Toggle between "debug mode" cursorline and "follow mode" cursorline. In
--- follow mode the current window jumps to the selected thread on every state
--- update.
function M.toggle_follow()
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


--- Jumps once to the selected thread's location, independent of follow mode.
function M.force_focus()
    if not M.core or not M.core.client then
        vim.notify("[DVAP-ui] Debug session is not connected, ignoring", vim.log.levels.INFO)
        return
    end

    M.thread_watch_pos_cache = { "", 0 }
    M.try_focus()
end


--- Reuses the existing qflist if its id matches the cached one (so repeated
--- invocations update in place instead of pushing new lists on the stack).
---@param cache_key string    Field on M that stores the qf list id
---@param items     table[]
local function show_qflist(cache_key, items)
    local cur_id = vim.fn.getqflist({ id = 0 }).id
    if M[cache_key] ~= nil and M[cache_key] == cur_id then
        vim.fn.setqflist({}, 'u', { id = cur_id, items = items })
        return
    end

    vim.fn.setqflist({}, ' ', { items = items })
    M[cache_key] = vim.fn.getqflist({ id = 0 }).id
    vim.cmd(":copen")
end


function M.set_breakpoint_qf()
    if not M.core then return end

    local items = {}
    for _, item in pairs(M.core.get_state().breakpoints) do
        table.insert(items, {
            filename = item.file_path,
            lnum     = item.line,
            text     = string.format("Enabled: %s, NoCond: %s", item.enabled, item.nonconditional),
        })
    end

    show_qflist("QF_breakpoint_id_cache", items)
end


function M.set_thread_qf()
    if not M.core then return end

    local state = M.core.get_state()

    local items = {}
    local rest  = {}
    for id, item in pairs(state.threads) do
        local flags = ""
        if id == state.selected then flags = flags .. " [SELECTED]" end
        if item.lost            then flags = flags .. " [LOST]"     end

        local entry = {
            filename = item.file_path,
            lnum     = item.line,
            text     = string.format("%s tid:%s%s", id, item.tid, flags),
        }

        if id == state.selected then
            table.insert(items, entry)
        else
            table.insert(rest, entry)
        end
    end
    vim.list_extend(items, rest)

    show_qflist("QF_thread_id_cache", items)
end


--- Copies "<absolute_path>:<line>" to the system clipboard.
local function copy_path_with_line()
    local file = vim.api.nvim_buf_get_name(0)
    if file == "" then
        vim.notify("[DVAP-ui] Buffer has no file", vim.log.levels.INFO)
        return
    end

    local line = vim.api.nvim_win_get_cursor(0)[1]
    vim.fn.setreg('+', string.format("%s:%d", file, line))
end


---@param config DvapUIConfig?
function M.setup(config)
    local ok
    ok, M.core = pcall(require, "nvim-dvap")
    if not ok then
        vim.notify("[DVAP-ui] nvim-dvap core not found", vim.log.levels.ERROR)
        M.core = nil
        return
    end

    M.config = vim.tbl_deep_extend("force", default_config, config or {})

    M.core.setup({
        on_connected       = M.start_ui_render,
        on_disconnected    = M.reset_ui,
        on_state_updated   = M.render,
        reconnect_interval = M.config.reconnect_interval,
    })

    vim.api.nvim_create_user_command('DVAPConnect',        M.connect_cmd,       {})
    vim.api.nvim_create_user_command('DVAPDisconnect',     M.disconnect_cmd,    {})
    vim.api.nvim_create_user_command('DVAPFocus',          M.force_focus,       {})
    vim.api.nvim_create_user_command('DVAPToggleFollow',   M.toggle_follow,     {})
    vim.api.nvim_create_user_command('DVAPBreakpointList', M.set_breakpoint_qf, {})
    vim.api.nvim_create_user_command('DVAPThreadList',     M.set_thread_qf,     {})
    vim.api.nvim_create_user_command('DVAPGetPathLine',    copy_path_with_line, {})

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
