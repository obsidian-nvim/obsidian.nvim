---
title: "Note"
tags:
  - notes
  - configuration
---

- [Default Note Template](#default-note-template)
- [Creation Callback](#creation-callback)
- [Creating and Saving Notes](#creating-and-saving-notes)
- [Inserting Text](#inserting-text)
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

## Creating and Saving Notes

Use `Note.resolve_path(opts)` to resolve a destination without creating a note or running creation callbacks. It follows the configured ID, path, and new-note-location settings. Invalid filenames raise an error unless you pass `prompt_invalid_filename = true`.

Use `Note.create { path = absolute_path }` for an exact destination that bypasses ID and path generation. Creation builds an in-memory note and runs the creation lifecycle; it does not write the file. For generated paths, `Note.create` prompts for invalid filenames by default; pass `prompt_invalid_filename = false` for automation.

Choose the persistence method based on the content you want:

- `note:write()` initializes missing notes with their configured template and applies the frontmatter policy.
- `note:save { content = text, insert_frontmatter = false }` replaces the body without applying a template or rewriting existing frontmatter. Pass an empty string or empty list to clear the body.
- `note:save { update_content = function(lines) ... end }` transforms existing body lines. Do not combine `content` and `update_content`.

`save()` returns the written lines, including frontmatter. It preserves modified buffer content when reading the existing note.

## Inserting Text

Use `note:insert_text(text, opts)` for a string, multiline string, or list of lines:

```lua
local row, col = note:insert_text("- Buy milk", {
  section = "Tasks",
  placement = "bot",
  include_children = true,
  ignore_case = true,
  spacing = "newline",
  on_section_missing = "error",
  insert_frontmatter = false,
})
```

| Option | Behavior |
| --- | --- |
| `target = "body"` | Insert at the beginning or end of the entire body, after frontmatter. |
| `section` | Select a heading by label, level, or both. Omit it to select the preamble before the first heading. |
| `placement = "top" / "bot"` | Prepend or append within the target. Defaults to `top`. |
| `include_children = true` | Append after descendant sections too. Defaults to `false`. |
| `ignore_case = true` | Match heading labels without regard to case. Defaults to `false`. |
| `spacing = "auto"` | Leave a blank line between existing and inserted content. |
| `spacing = "newline"` | Separate content with a newline. |
| `spacing = "inline"` | Add no separator. |
| `on_section_missing` | `create` (default), `error`, or `cancel`. |

Omit `spacing` to retain the existing section layout rules. Existing callers keep their preamble targeting and padding behavior. Section parsing excludes headings inside code blocks and supports setext headings.

Insertion accepts the save options `path`, `insert_frontmatter`, `frontmatter`, and `check_buffers`. It manages the content transformation itself, so do not supply `content` or `update_content`.

The return values are a 1-based row, including frontmatter, and a 0-based byte column. Empty or cancelled insertions return `0, 0`.

You can also navigate when opening a note with `note:open { anchor = "Heading" }` or `note:open { block = "block-id" }`. Opening resolves these targets against the current buffer or file content.

## Deleting Notes

Use the `delete_note` code action to delete the current note. It calls `Note.delete()`, asks you to confirm permanent deletion, warns you about backlinks, and lets you delete linked attachments. Run it through your LSP code action picker or directly:

```lua
require("obsidian.actions").delete_note()
```

Scripts can call `note:delete()` directly and inspect the returned deletion result.

Support for deleting notes through LSP-aware file browsers is on the roadmap. Until then, use the `delete_note` action so declining a confirmation prevents deletion.

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

## See also

[[Frontmatter]] · [[Template]] · [[Workspace]]
