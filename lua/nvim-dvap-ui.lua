-- Main module for the Hello World plugin
-- Timer = vim.uv.new_timer()
-- DVAP_namespace = vim.api.nvim_create_namespace("dvap")
-- 
-- Thread_buf_cache = {}
-- Thread_Watch_num = nil
-- Thread_Watch_pos_cache = { "", 0 }
-- 
-- CursorLineCache = nil
-- CursorLineHLCache = nil
-- vim.api.nvim_get_hl(0, { name = 'CursorLine' } )
-- DVAP_CursorLine_hl = { bg = '#19435b' }
-- 
-- -- Define the sign
-- vim.fn.sign_define("DVAP_breakpoint_unconditional", { text = "", texthl = "Search" })
-- vim.fn.sign_define("DVAP_breakpoint_conditional", { text = "", texthl = "Search" })

local M = {
    thread_buf_cache = {},
    thread_watch_num = {},
    thread_watch_pos_cache = { "", 0 },

    cursor_line_opt_cache = nil,
    cursor_line_hl_cache = nil,

    core = nil,

    timer = vim.uv.new_timer(),
    DVAP_namespace = vim.api.nvim_create_namespace("dvap"),
    DVAP_CursorLine_hl = { bg = '#19435b' },

    QF_breakpoint_id_cache = nil
}

function M.highlight_current_line(thread_num, file_path, line_number)
    local bufnr = vim.fn.bufadd(file_path)
    vim.fn.bufload(bufnr)

    vim.api.nvim_buf_set_extmark(bufnr, M.DVAP_namespace, line_number - 1, 0, {
        line_hl_group = "Search",
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
    if M.thread_Watch_pos_cache[1] == file_path and M.thread_Watch_pos_cache[2] == line_number then
        return
    end

    local bufnr = vim.fn.bufadd(file_path)
    vim.fn.bufload(bufnr)

    vim.api.nvim_set_current_buf(bufnr)

    vim.api.nvim_win_set_cursor(0, { tonumber(line_number), 0 })
    M.Thread_Watch_pos_cache[1] = file_path
    M.Thread_Watch_pos_cache[2] = line_number
end

function M.try_focus()
    local threads = M.core.get_state().threads

    if M.thread_Watch_num ~= nil and threads[M.thread_Watch_num] ~= nil then
        M.thread_watch_focus(threads[M.thread_Watch_num]["file_path"], M.threads[M.thread_Watch_num]["line"])
        return
    end

    --try tid
    for _, thread in pairs(threads) do
        if thread["tid"] == M.thread_Watch_num then
            M.thread_watch_focus(thread["file_path"], thread["line"])
        end
    end

end

function M.rerender(state)
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
            b_sign = "DVAP_breakpoint_unconditional"
        else
            b_sign = "DVAP_breakpoint_conditional"
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

    vim.api.nvim_set_hl(0, 'CursorLine', M.DVAP_CursorLine_hl)
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
        prompt = 'Enter DVAP endpoint (HOST:PORT): ',
        default = "127.0.0.1:8080", -- значение по умолчанию
    }, M.connect)
end

function M.set_watch_thread()
    vim.ui.input({
        prompt = 'Enter Focus Thread num|tid: ',
        default = "1", -- значение по умолчанию
    }, function(num)
        M.thread_watch_num = num
        M.thread_watch_pos_cache = { "", 0 }
    end)
end


function M.Reset_watch_thread()
    M.thread_watch_num = nil
    M.thread_watch_pos_cache = { "", 0 }
end


function M.update_breakpoint_qf()
    local breakpoints = M.core.get_state().breakpoints

    -- 1. Подготовка данных в формате quickfix
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

    -- 2. Поиск окна quickfix для сохранения позиции
    local qf_id = vim.fn.getqflist({id = 0}).id
    if M.QF_breakpoint_id_cache ~= nil and M.QF_breakpoint_id_cache == qf_id then
        vim.fn.setqflist({}, 'u', { id = qf_id, items = qf_items })
        return
    end

    vim.fn.setqflist({}, ' ')
    M.QF_breakpoint_id_cache = vim.fn.getqflist({id = 0}).id
end

function M.update_thread_qf()
    local threads = M.core.get_state().threads

    -- 1. Подготовка данных в формате quickfix
    local qf_items = {}
    for _, item in pairs(threads) do
        table.insert(qf_items, {
            filename = item.file_path,
            lnum = item.line,
            text = string.format("Tid: %s", item.tid),
        })
    end

    -- 2. Поиск окна quickfix для сохранения позиции
    local qf_id = vim.fn.getqflist({id = 0}).id
    if M.QF_breakpoint_id_cache ~= nil and M.QF_breakpoint_id_cache == qf_id then
        vim.fn.setqflist({}, 'u', { id = qf_id, items = qf_items })
        return
    end

    vim.fn.setqflist({}, ' ')
    M.QF_breakpoint_id_cache = vim.fn.getqflist({id = 0}).id
end


-- Function to set up the plugin
function M.setup()
    local ok
    ok, M.core = pcall(require, "nvim-DVAP")
    if not ok then
        vim.notify("nvim-DVAP core dont found", 4)
        return
    end

    M.core.setup({
        on_connected    = M.start_ui_render,
        on_disconnected = M.stop_ui.render,
        on_update_state = M.rerender
    })

    vim.keymap.set("n", "<leader>dc",  M.connectCMD)
    vim.keymap.set("n", "<leader>dd",  M.core.disconnect)
    vim.keymap.set("n", "<leader>dw",  M.set_watch_thread)
    vim.keymap.set("n", "<leader>df",  M.try_focus)
    vim.keymap.set("n", "<leader>dr",  M.Reset_watch_thread)

    vim.keymap.set("n", "<leader>dqb", M.update_breakpoint_qf)
    vim.keymap.set("n", "<leader>dqt", M.update_thread_qf)

end

-- Return the module
return M

