## NVIM-DVAP-UI

This is the DVAP client UI implementation for Neovim.

WARNING — This implementation is a work in progress; DON'T use it unless you intend to participate in its development.

## References

- https://github.com/Isletier/DVAP - Adapter for GDB (please read this first).
- https://github.com/Isletier/nvim-DVAP - The core client component for this plugin.

## Installation

Example for packer.nvim:

```lua
use {
    'Isletier/nvim-DVAP-ui'
    requires = {
       'Isletier/nvim-DVAP'
    },
}
```

I have no idea how it's done for other package managers, but I'm sure you will figure it out.

## Configuration

```lua

require("nvim-dvap-ui").setup() -- default setup

-- All configuration options with their defaults:
require("nvim-dvap-ui").setup({
    -- Default host suggested for the connect command
    default_host = "127.0.0.1",

    -- Default port suggested for the connect command
    default_port = 9000,

    -- Highlight for the cursor line to mark the start of "debug" mode
    debug_cursorline_hl = get_default_threadline_hl(),
    
    -- Left column sign to mark an unconditional breakpoint position
    breakpoint_unconditional_sign = "DVAP_breakpoint_unconditional",
    -- vim.fn.sign_define("DVAP_breakpoint_unconditional", { text = "B", texthl = "Character" })

    -- Left column sign to mark a conditional breakpoint position
    -- Note: Separation of conditional/unconditional breakpoints is not guaranteed; it may fallback to unconditional.
    breakpoint_conditional_sign = "DVAP_breakpoint_conditional",
    -- vim.fn.sign_define("DVAP_breakpoint_conditional", { text = "C", texthl = "Character" })

    -- Whether to set default keymaps
    set_default_keymaps = true,
    -- Default mappings:
    -- vim.keymap.set("n", "<leader>dc",  "<cmd>DVAPConnect<CR>")
    -- vim.keymap.set("n", "<leader>dd",  "<cmd>DVAPDisconnect<CR>")
    -- vim.keymap.set("n", "<leader>dw",  ":DVAPWatch ")
    -- vim.keymap.set("n", "<leader>df",  "<cmd>DVAPFocus<CR>")
    -- vim.keymap.set("n", "<leader>dr",  "<cmd>DVAPResetWatch<CR>")
    -- vim.keymap.set("n", "<leader>dp",  "<cmd>DVAPGetPathLine<CR>")
    -- vim.keymap.set("n", "<leader>dqb", "<cmd>DVAPBreakpointList<CR>")
    -- vim.keymap.set("n", "<leader>dqt", "<cmd>DVAPThreadList<CR>")

    -- Highlight group to mark current thread positions
    threadline_hl = "Search"
})
```

## Usage & Commands

- **DVAPConnect**

Opens a UI prompt to enter the host and port for the debug session.

- **DVAPDisconnect**

Disconnects from the current session.

- **DVAPWatch {thread_num|tid}**

Sets the watched thread. This automatically moves the cursor when the thread's position is updated.

Note: This does not switch the active thread in your debugger.

- **DVAPFocus**

Moves the cursor to the position of the currently watched thread.

- **DVAPResetWatch**

Clears the current thread watch.

- **DVAPGetPathLine**

A helper command that copies the current path:line to the system clipboard.

- **DVAPBreakpointList**

Lists all breakpoints and their positions in the Quickfix (QF) list.

- **DVAPThreadList**

Lists all threads and their positions in the Quickfix (QF) list.

