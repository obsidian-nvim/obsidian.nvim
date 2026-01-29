```lua
---@class obsidian.config.NoteOpts
---
---Default template to use, relative to template.folder or an absolute path.
---@field template string|?
note = {
  template = (function()
    local root = vim.iter(vim.api.nvim_list_runtime_paths()):find(function(path)
      return vim.endswith(path, "obsidian.nvim")
    end)
    if not root then
      return nil
    end
    return vim.fs.joinpath(root, "data/default_template.md")
  end)(),
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
    -- template = vim.NIL, -- disables the default note template and just use a blank note
    template = "default.md", -- A template you can define your self
  },
}
```


For fields you have access to for the default template, see [[Template]].

