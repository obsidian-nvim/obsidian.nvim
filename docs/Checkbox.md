```lua
---@class obsidian.config.CheckboxOpts
---
---@field enabled? boolean
---
---Order of checkbox state chars, e.g. { " ", "x" }, "" means a list item
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

## Checkbox to list item

You can also include an empty string in `checkbox.order` (e.g. `{ " ", "x", "" }`) to rotate a checkbox back into a plain list item (e.g. `- [x] foo` -> `- foo`).
