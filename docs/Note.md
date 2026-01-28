```lua
---@class obsidian.config.NoteOpts
---
---Default template to use, relative to template.folder or an absolute path.
---@field template string|?
note = {
  template = nil,
}
```

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
    template = vim.NIL,
  },
}
```

