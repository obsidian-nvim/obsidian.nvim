[Options](#Options)

## Link Format

`opts.link.format` defaults to `"shortest"` like obsidian app, valid values:

- `shortest`: shortest file path when possible.
- `relative`: relative path from the current note file.
- `absolute`: vault-relative absolute path.

## Link Style

`opts.link.style` can be either `"wiki"`, `"markdown"` or a custom function that accepts the following type and return a string:

```lua
---@class obsidian.link.LinkCreationOpts
---@field label? string
---@field path? obsidian.Path|string|?
---@field anchor? obsidian.note.HeaderAnchor|?
---@field block? obsidian.note.Block|?
---@field style? obsidian.link.LinkStyle
---@field format? obsidian.link.LinkFormat
---@field raw_path? obsidian.Path|string|?
```

Default wiki link in the form of `[[foo-bar|Foo Bar]]`, where the former part is the file basename without suffix, and latter is the label extracted from the note object, if label is identical to basename, latter part is omitted.

You can optionally swap implementation to one of the following or your own:

```lua

-- '[[Foo Bar]]'
---@param opts obsidian.link.LinkCreationOpts
---@return string
local wiki_link_alias_only = function(opts)
  ---@type string
  local header_or_block = ""
  if opts.anchor then
    header_or_block = string.format("#%s", opts.anchor.header)
  elseif opts.block then
    header_or_block = string.format("#%s", opts.block.id)
  end
  return string.format("[[%s%s]]", opts.label, header_or_block)
end

-- '[[foo-bar.md|Foo Bar]]'
---@param opts obsidian.link.LinkCreationOpts
---@return string
local wiki_link_path_only = function(opts)
  ---@type string
  local header_or_block = ""
  if opts.anchor then
    header_or_block = opts.anchor.anchor
  elseif opts.block then
    header_or_block = string.format("#%s", opts.block.id)
  end
  return string.format("[[%s%s]]", opts.path, header_or_block)
end

-- '[[foo-bar.md]]'
---@param opts obsidian.link.LinkCreationOpts
---@return string
local wiki_link_path_prefix = function(opts)
  local anchor = ""
  local header = ""
  if opts.anchor then
    anchor = opts.anchor.anchor
    header = string.format(" ❯ %s", opts.anchor.header)
  elseif opts.block then
    anchor = "#" .. opts.block.id
    header = "#" .. opts.block.id
  end

  if opts.label ~= opts.path then
    return string.format("[[%s%s|%s%s]]", opts.path, anchor, opts.label, header)
  else
    return string.format("[[%s%s]]", opts.path, anchor)
  end
end

require("obsidian").setup {
  link = {
    style = wiki_link_alias_only,
    -- style = wiki_link_path_only
    -- style = wiki_link_path_prefix
  },
}
```

## Link Rename

See [LSP rename](LSP.md#rename)

## Options

```lua
---@alias obsidian.link.LinkStyle "wiki" | "markdown" | fun(opts: obsidian.link.LinkCreationOpts): string
---@alias obsidian.link.LinkFormat "shortest" | "relative" | "absolute"

---@class obsidian.config.LinkOpts
---@field style? obsidian.link.LinkStyle
---@field format? obsidian.link.LinkFormat
link = {
  style = "wiki",
  format = "shortest",
}
```
