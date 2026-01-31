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

## Code Actions

obsidian.nvim exposes a small set of LSP code actions for common note operations. You can trigger them using your normal LSP code action keymap, by default neovim maps `vim.lsp.buf.code_action` to `gra`.

Available actions:

- Normal mode:
  - Rename current note (`rename`)
  - Insert template at cursor (`insert_template`)
  - Add file property (`add_property`)
- Visual mode:
  - Link selection as name for an existing note (`link`)
  - Link selection as name for a new note (`link_new`)
  - Extract selected text to a new note (`extract_note`)
