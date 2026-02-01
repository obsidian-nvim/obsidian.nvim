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

### Code Action API

You can register custom code actions via `require("obsidian").code_action`. Each action is exposed as an LSP
command, so register actions before calling `require"obsidian".setup{}`.

API:

- `require("obsidian").code_action.add(opts)`, and `opts` field have following fields:
  - `name`: command id (snake_case recommended).
  - `title`: text shown in the code action picker.
  - `fn`: function invoked when the action is executed.
  - `range` (optional): when `true`, the action only appears for a visual selection.
- `require("obsidian").code_action.del(name)` removes a previously registered action.

<!-- Example: -->
<!---->
<!-- ```lua -->
<!-- require("obsidian").code_action.add { -->
<!--   name = "insert tag", -->
<!--   title = "Insert an existing tag", -->
<!--   fn = require("obsidian.actions").insert_tag, -->
<!-- } -->
<!-- ``` -->
