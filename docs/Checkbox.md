```lua
---@class obsidian.config.CheckboxOpts
---
---@field enabled? boolean
---
---Order of checkbox state chars, e.g. { " ", "x" }
---@field order? string[]
---
---Whether to create new checkbox on paragraphs
---@field create_new? boolean
checkbox = {
  enabled = true,
  create_new = true,
  order = { " ", "~", "!", ">", "x" },
}
```

## Create new

By default, `Obsidian toggle_checkbox` and `smart_action` works like default `<C-l>` keybind in obsidian app, it will add a checkbox on normal paragraphs. This behavior can be changed by setting `checkbox.create_new` to `false`.
