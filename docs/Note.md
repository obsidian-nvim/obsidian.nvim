- [Default Note Template](#default-note-template)
- [Creation Callback](#creation-callback)
- [Note ID Presets](#note-id-presets)
- [Options](#options)

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
}
```
