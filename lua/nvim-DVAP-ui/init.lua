-- Main module for the Hello World plugin
local M = {}

-- Function to set up the plugin
function M.setup()
    local ok, base = pcall(require, "nvim-DVAP")
    if not ok then
        vim.notify("Бля, ты забыл подключить plugin-base!", 4)
        return
    end

    base.setup()
end

-- Return the module
return M
