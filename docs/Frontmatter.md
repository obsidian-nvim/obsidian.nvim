```lua
---@class obsidian.config.FrontmatterOpts
---
--- Whether to enable frontmatter, boolean for global on/off, or a function that takes filename and returns boolean.
---@field enabled? (fun(fname: string?): boolean)|boolean
---
--- Function to turn Note attributes into frontmatter.
---@field func? fun(note: obsidian.Note): table<string, any>
--- Function that is passed to table.sort to sort the properties, or a fixed order of properties.
---
--- List of string that sorts frontmatter properties, or a function that compares two values, set to vim.NIL/false to do no sorting
---@field sort? string[] | (fun(a: any, b: any): boolean) | vim.NIL | boolean
frontmatter = {
  enabled = true,
  func = require("obsidian.builtin").frontmatter,
  sort = { "id", "aliases", "tags" },
}
```
---

obsidian.nvim reads YAML frontmatter at the top of a note (between `---` lines). It validates a small set of keys used by the plugin and leaves any other fields untouched as metadata.

## Special keys

- `id`: string or number
- `aliases`: string or list of strings
- `tags`: string or list of strings

Invalid types are ignored with a warning.

## Example

```markdown
---
id: 2024-09-01
aliases:
  - "Weekly review"
tags: [work, planning]
status: draft
---
```

## Disabling frontmatter

If you do not want frontmatter parsing for a workspace, set `frontmatter.enabled = false`.

```lua
require("obsidian").setup {
  frontmatter = { enabled = false }, -- globally
  workspaces = {
    {
      path = "~/Documents/Notes",
      name = "Notes",
      overrides = {
        frontmatter = { enabled = false }, -- for this workspace
      },
    },
  },
}
```

Optionally `enabled` can also take a function that received the note filename and returns a boolean:

```lua
require("obsidian").setup {
  frontmatter = {
    enabled = function(path)
      if vim.endswith(tostring(path), ".qmd") then -- disables the frontmatter when it is quarto file
        return false
      end
      return true
    end,
  },
}
```

> [!Warning]
> this signature of this callback could change in the future.

## Sorting frontmatter

TODO:
