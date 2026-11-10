---
title: "Note"
tags:
  - notes
  - configuration
---

- [Default Note Template](#default-note-template)
- [Creation Callback](#creation-callback)
- [Deleting Notes](#deleting-notes)
- [Note ID Presets](#note-id-presets)
- [Options](#options)
- [See also](#see-also)

## Default Note Template

The "default default template" when creating notes look like the following for historical and practical reasons:

```markdown
---
id: {{id}}
aliases:
  - {{title}}
tags: []
---
```

You can control the style of your default notes created by `:Obsidian new` with `opts.note.template`

```lua
require("obsidian").setup {
  note = {
    -- template = vim.NIL, -- disables the default note template and just use a blank note
    template = "default.md", -- A template you can define your self
  },
}
```

For fields you have access to for the default template, see [[Template]].

## Creation Callback

`opts.callbacks.create_note` runs whenever `Note.create` builds a note object. The second argument currently contains `scope`, an arbitrary string inherited from the `Note.create` opts, defaulting to `"plain"`. Built-in explicit scopes are `"daily"` and `"unique"`; user code can pass any scope like `"media"` or `"meeting"`.

The same hook is also exposed as the `ObsidianNoteCreate` `User` autocmd. Its `ev.data` contains a note snapshot and opts: `{ note = note, opts = opts }`.

For example, whenever a unique note is created, prompt for a label, add it as an alias, update the note frontmatter, then add a labeled link to today's daily note under `## TIL` using the note text insertion API:

```lua
require("obsidian").setup {
  callbacks = {
    create_note = function(note, opts)
      if opts.scope ~= "unique" then
        return
      end

      local label = vim.trim(vim.fn.input "Label: ")
      if label == "" then
        return
      end

      note:add_alias(label)
      note:write() -- persist the new alias/frontmatter

      local link = note:format_link { label = label }
      local daily = require("obsidian.daily").today()
      if not daily:exists() then
        daily = daily:write()
      end

      daily:insert_text({ "- " .. link }, {
        section = { header = "TIL", level = 2 },
        placement = "bot",
      })
    end,
  },
}
```

Plugins or scripts that call `Note.create` can set their own scope:

```lua
-- you can build your own action/command/keymap around this, and then script custom hooks in opt.callbacks.create_note
local note = require("obsidian.note").create {
  title = "The Wire",
  template = "TV show.md"
  scope = "media",
}
```

## Deleting Notes

Use the `delete_note` code action to delete the current note. It calls `Note.delete()`, asks you to confirm permanent deletion, warns you about backlinks, and lets you delete linked attachments. Run it through your LSP code action picker or directly:

```lua
require("obsidian.actions").delete_note()
```

Scripts can call `note:delete()` directly and inspect the returned deletion result.

Support for deleting notes through LSP-aware file browsers is on the roadmap. Until then, use the `delete_note` action so declining a confirmation prevents deletion.

## Renaming the first heading with the note

When `note.sync_heading` is `true` (default `false`), `:Obsidian rename` also renames the first heading of the note if it is equal to the old `id`. The links naming it (`[[Note#Heading]]`, `[[#Heading]]`) are rewritten in the same edit as the file rename, so they keep pointing at it. A first heading that differs from the `id` is left alone, and a new name that collides with another heading of the note leaves the heading as it was and logs an error.

```lua
require("obsidian").setup {
  note = { sync_heading = true },
}
```

Pair it with `frontmatter.sync_title` to keep the `title` property in step as well; see [[Frontmatter#Keeping title in step with id|Frontmatter]].

## Renaming the file with the first heading

When `note.sync_filename` is `true` (default `false`), renaming the first heading of a note with `vim.lsp.buf.rename()` also renames the note file if the heading equals the file name without extension. The file goes through `Note:rename`, so backlinks, the `id` and, with `frontmatter.sync_title`, the `title` follow it. A heading that differs from the file name, or is not the first one, leaves the file alone. When a note with the new name already exists nothing is renamed and the error `Heading "<old>" not renamed: Note with same name exists` is logged.

```lua
require("obsidian").setup {
  note = { sync_filename = true },
}
```

## Note ID Presets

By default obsidian.nvim uses random zettel IDs. (**Legacy design decision, in 4.0.0 will be default to human readable input title**)

If you want readable UTF-8 title-based IDs (works across scripts), use the built-in preset:

```lua
require("obsidian").setup {
  note_id_func = require("obsidian.builtin").title_id,
}
```

Examples:

- `"Hello, world"` -> `"hello-world"`
- `"Привет, мир"` -> `"привет-мир"`
- `"你好 世界"` -> `"你好-世界"`

When creating notes in a directory where the slug already exists, this preset appends a numeric suffix (`-2`, `-3`, ...).

## Options

```lua
---@class obsidian.config.NoteOpts
---
---Default template to use, relative to template.folder or an absolute path.
---
---@field template string|?
---
---Whether the first heading of a note equal to its `id` is renamed along with the note, together with the links naming it.
---@field sync_heading? boolean
---
---Whether renaming the first heading of a note, when it equals the file name, also renames the note file (with its backlinks, `id`, and `title` when `frontmatter.sync_title` is set).
---@field sync_filename? boolean
note = {
  template = (function()
    local root
    for _, path in ipairs(vim.api.nvim_list_runtime_paths()) do
      if vim.endswith(path, "obsidian.nvim") then
        root = path
        break
      end
    end
    if not root then
      return nil
    end
    return vim.fs.joinpath(root, "data/default_template.md")
  end)(),
  sync_heading = false,
  sync_filename = false,
}
```

## See also

[[Frontmatter]] · [[Template]] · [[Workspace]]
