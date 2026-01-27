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
