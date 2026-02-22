## NVIM-DVAP-UI

This is DVAP client ui implementation for Neovim.

**WARNING** — this implementation is very WIP and partially vibecoded; DON'T use it unless you want to participate in its development.

## References

- https://github.com/Isletier/DVAP - adapter for GDB (please, read this one)
- https://github.com/Isletier/nvim-DVAP - core client part for this plugin

## Installation

this is for packer:

```lua
use {
    'Isletier/nvim-DVAP-ui'
    requires = {
       'Isletier/nvim-DVAP'
    },
}
```

## Configuration

```lua

require("nvim-dvap-ui").setup() -- default setup

-- all of the configuration with defaults
    require("nvim-dvap-ui").setup({
    -- default host that will be emmited for connect cmd
    default_host = "127.0.0.1",

    -- default port that will be emmited for connect cmd
    default_port = 9000,

    -- highlight for the cursor line to mark start of "debug" mode
    debug_cursorline_hl = get_default_threadline_hl(),
    
    -- left column sign to mark breakpoint position
    breakpoint_unconditional_sign = "DVAP_breakpoint_unconditional",
    --  vim.fn.sign_define("DVAP_breakpoint_unconditional", { text = "B", texthl = "Character" })


    -- left column sign to mark conditional breakpoint position
    -- Note: separation of condiitonal|uncoditional breakpoints is not guarantied, it fallbacks to unconditional one
    breakpoint_conditional_sign = "DVAP_breakpoint_conditional",
    -- vim.fn.sign_define("DVAP_breakpoint_conditional",   { text = "C", texthl = "Character" })

    -- to set default keymaps, or not
    set_default_keymaps = true,
    -- vim.keymap.set("n", "<leader>dc",  "<cmd>DVAPConnect<CR>")
    -- vim.keymap.set("n", "<leader>dd",  "<cmd>DVAPDisconnect<CR>")
    -- vim.keymap.set("n", "<leader>dw",  ":DVAPWatch ")
    -- vim.keymap.set("n", "<leader>df",  "<cmd>DVAPFocus<CR>")
    -- vim.keymap.set("n", "<leader>dr",  "<cmd>DVAPResetWatch<CR>")
    -- vim.keymap.set("n", "<leader>dp",  "<cmd>DVAPGetPathLine<CR>")

    -- vim.keymap.set("n", "<leader>dqb", "<cmd>DVAPBreakpointList<CR>")
    -- vim.keymap.set("n", "<leader>dqt", "<cmd>DVAPThreadList<CR>")

    -- Highlight group to mark current threads positions
    threadline_hl = "Search"
})
```

## Usage, commands

- **DVAPConnect**

Starts ui prompt for debug session host:port to attach.

- **DVAPDisconnect**

Disconnects from the session.

- **DVAPWatch {thread_num|tid}**

Sets wathced thread, changes cursor position when threads position update occures

Note: this is no-way related to switching active thread in your debugger, and doesn't meant to be.

- **DVAPFocus**

Changes cursor position to currently watched num.

- **DVAPResetWatch**

Resets thread watch

- **DVAPGetPathLine**

Helper command to paste cuurent `path:line` to your systems copy buffer.

- **DVAPBreakpointList**

List all breakpoints and their positions in the QF.

- **DVAPThreadList**

List all threads and their positions in the QF.

