See [[LSP Progress]]

## Definition

There are three types of links supported:

- Internal Link
  - `[markdown note](markdown%20note.md)`
  - `[[wiki note]]`
- Attachment Link
  - `[image file](image%file.md)`
  - `[[image file]]`
- URI
  - `[uri](scheme:xyz)`

Bare Links in the wild like `https://nevoim.io`, `mailto:example@gmail.com` and `file:///home/username/.vimrc` are not supported, , to open them, use neovim default keymaps like `gx` and `gf`, or you can enclose them in markdown links.

Attachments and URIs are opened with neovim's default `vim.ui.open`, to customize the behavior, see [[Attachment#open]]

## Rename

Use `vim.lsp.buf.rename()` or default neovim mapping `grn` to rename the target note and update all references across your vault.

The note to be renamed is either the note that the link under your cursor points to, or your current buffer note.

## Auto Rename

When a `.md` file is renamed (e.g. via a file explorer or `:mv`), the LSP server detects the rename and updates all links pointing to that note across your vault.

By default you will be prompted to confirm before links are updated. To apply updates automatically without confirmation, set:

```lua
require("obsidian").setup {
  link = {
    auto_update = true,
  },
}
```
