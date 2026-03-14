# bin-comm.nvim

Neovim plugin that adds a `:Comm` command for comparing the contents of two diff buffers using /bin/comm.  It's useful to see what lines exist only on the first file, both files, and second file.

## Installation

With `lazy.nvim`:

```lua
{
  "paxunix/bin-comm.nvim",
  cmd = "Comm",
}
```

Using `cmd = "Comm"` tells `lazy.nvim` to load the plugin only when the `:Comm` command is invoked.

## Usage

Open exactly two buffers in diff mode, then run:

```vim
:Comm
```

The command opens three result buffers:

- `ONLY-<left>`
- `BOTH-<left>+<right>`
- `ONLY-<right>`

Input is normalized before comparison:

- leading and trailing whitespace is trimmed
- internal whitespace runs are collapsed to a single space
- duplicate lines are removed

If `diffopt` includes `icase`, comparisons are case-insensitive.
