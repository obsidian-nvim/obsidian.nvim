## Customizing Links

Default `opts.link.wiki` and `opts.link.markdown` accept a function that gets an options table and outputs.

Default wiki link in the form of `[[foo-bar|Foo Bar]]`, where the former part is the file basename without suffix, and latter is the label extracted from the note object.

```lua
---@class obsidian.link.LinkCreationOpts
---@field label? string
---@field path? obsidian.Path|string|?
---@field anchor? obsidian.note.HeaderAnchor|?
---@field block? obsidian.note.Block|?
---@field style? "wiki" | "markdown"
```

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
```
