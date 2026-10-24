---
title: "LSP"
tags:
  - lsp
  - reference
---

See also: [[LSP-Progress]]

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

Use `vim.lsp.buf.rename()` or default neovim mapping `grn` to rename the element under the cursor and update all references across your vault. On plain text it answers "Nothing to rename".

| Under the cursor                             | What is renamed                                                                                                                               |
| -------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| A link to a note                             | The linked note, and every link to it                                                                                                         |
| A block id `^id`, or `[[#^id]]`              | The id and every `[[Note#^id]]`, `![[Note#^id]]`, `[[#^id]]`, `[x](Note.md#^id)` (letters, digits and `-` only)                               |
| A heading (ATX or setext), or `[[#Heading]]` | The heading text, keeping its level or underline, and every link component naming it, in the style it was written (text, slug or URL-encoded) |
| A footnote `[^name]`                         | The definition and every reference in the same note                                                                                           |
| A tag `#a/b`, inline or in `tags:`           | The tag and every tag below it (`a/b/c`) in the whole vault. Renaming onto an existing tag merges the two                                     |
| A link to an attachment                      | The attachment file and every reference to it, keeping its extension when the new name has none                                               |

A block id or heading that already exists in the note is refused, and so is a heading that is not unique in the note. After a tag merge a note can list the same tag twice in its frontmatter. Only renaming a note or an attachment renames a file, and no rename adds frontmatter fields.

To rename the note of the current buffer, wherever the cursor is, use `:Obsidian rename [NEWNAME]`.

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

## Code Actions

obsidian.nvim exposes a small set of LSP code actions for common note operations. You can trigger them using your normal LSP code action keymap, by default neovim maps `vim.lsp.buf.code_action` to `gra`.

Available actions:

- Normal mode:
  - Add file property (`add_property`)
  - Add attachment from folder, filepath or url (`add_attachment`)
  - Start/stop recording audio as attachment (`toggle_recording`, title changes with recording state)
  - Insert template at cursor (`insert_template`, requires templates enabled)
  - Move current note to another folder (`move_note`)
  - Delete current note (`delete_note`)
  - Merge current note into another note (`merge_note`)
  - Start presentation (`start_presentation`, requires slides enabled)
  - List unlinked outgoing mentions in the current note, grouped by target note (`link_suggestions`, requires cache)
  - List unlinked incoming mentions of the current note in other notes (`backlink_suggestions`, requires cache)
  - Insert internal link at cursor (`insert_link`)
  - Remove the link under the cursor, preserving its display text (`unlink`)
  - Insert tag at cursor (`insert_tag`)
  - Add tag to frontmatter (`add_tag`)
  - Link word under cursor to an existing note (`link`)
  - Link word under cursor to a new note (`link_new`)
- Visual mode:
  - Link selection as name for an existing note (`link`)
  - Link selection as name for a new note (`link_new`)
  - Extract selected text to a new note (`extract_note`)

### Code Action API

You can register custom code actions via `require("obsidian").code_action` module.

API:

- `require("obsidian").code_action.add(opts)`, and `opts` field have following fields:
  - `name`: command id (snake_case recommended).
  - `title`: text shown in the code action picker, or a function that receives the current note and returns the text.
  - `fn`: function invoked when the action is executed.
  - `cond` (optional): a filter function that gets the current note object, determines whether actions is listed.
- `require("obsidian").code_action.del(name)` removes a previously registered action.

## See also

[[Completion]] · [[Actions]] · [[LSP-Progress]]
