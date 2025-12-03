---builtin functions that are default values for config options
local M = {}

---@class obsidian.link.LinkCreationOpts
---@field label? string
---@field path? obsidian.Path|string|?
---@field anchor? obsidian.note.HeaderAnchor|?
---@field block? obsidian.note.Block|?
---@field style? "wiki" | "markdown"

---Create a new unique Zettel ID.
---
---@return string
M.zettel_id = function()
  local suffix = ""
  for _ = 1, 4 do
    suffix = suffix .. string.char(math.random(65, 90))
  end
  return tostring(os.time()) .. "-" .. suffix
end

-- ---@param opts obsidian.link.LinkCreationOpts
-- ---@return string
-- M.wiki_link_alias_only = function(opts)
--   ---@type string
--   local header_or_block = ""
--   if opts.anchor then
--     header_or_block = string.format("#%s", opts.anchor.header)
--   elseif opts.block then
--     header_or_block = string.format("#%s", opts.block.id)
--   end
--   return string.format("[[%s%s]]", opts.label, header_or_block)
-- end

---NOTE: more close to what should be default
-- ---@param opts obsidian.link.LinkCreationOpts
-- ---@return string
-- M.wiki_link = function(opts)
--   ---@type string
--   local header_or_block = ""
--   if opts.anchor then
--     header_or_block = opts.anchor.anchor
--   elseif opts.block then
--     header_or_block = string.format("#%s", opts.block.id)
--   end
--   return string.format("[[%s%s]]", opts.path, header_or_block)
-- end

-- ---@param opts obsidian.link.LinkCreationOpts
-- ---@return string
-- M.wiki_link_path_prefix = function(opts)
--   local anchor = ""
--   local header = ""
--   if opts.anchor then
--     anchor = opts.anchor.anchor
--     header = util.format_anchor_label(opts.anchor)
--   elseif opts.block then
--     anchor = "#" .. opts.block.id
--     header = "#" .. opts.block.id
--   end
--
--   if opts.label ~= opts.path then
--     return string.format("[[%s%s|%s%s]]", opts.path, anchor, opts.label, header)
--   else
--     return string.format("[[%s%s]]", opts.path, anchor)
--   end
-- end

---@param anchor obsidian.note.HeaderAnchor
---@return string
local format_anchor_label = function(anchor)
  return string.format(" ❯ %s", anchor.header)
end

---@param opts obsidian.link.LinkCreationOpts
---@return string
M.wiki_link = function(opts)
  local anchor = ""
  local header = ""
  if opts.anchor then
    anchor = opts.anchor.anchor
    header = format_anchor_label(opts.anchor)
  elseif opts.block then
    anchor = "#" .. opts.block.id
    header = "#" .. opts.block.id
  end

  local format

  ---@diagnostic disable-next-line: param-type-mismatch
  if opts.label ~= vim.fs.basename(opts.path) then -- HACK: right???
    format = "[[%s%s|%s%s]]"
  else
    format = "[[%s%s]]"
  end
  return string.format(format, opts.path, anchor, opts.label, header)
end

---@param opts obsidian.link.LinkCreationOpts
---@return string
M.markdown_link = function(opts)
  local anchor = ""
  local header = ""
  if opts.anchor then
    anchor = opts.anchor.anchor
    header = format_anchor_label(opts.anchor)
  elseif opts.block then
    anchor = "#" .. opts.block.id
    header = "#" .. opts.block.id
  end

  return string.format("[%s%s](%s%s)", opts.label, header, opts.path, anchor)
end

---@param path string
---@return string
M.img_text_func = function(path)
  local format_string = {
    markdown = "![](%s)",
    wiki = "![[%s]]",
  }
  local style = Obsidian.opts.link.style
  local name = vim.fs.basename(tostring(path))

  if style == "markdown" then
    name = require("obsidian.util").urlencode(name)
  end

  return string.format(format_string[style], name)
end

---@param note obsidian.Note
---@return table<string, any>
M.frontmatter = function(note)
  local out = { id = note.id, aliases = note.aliases, tags = note.tags }
  if note.metadata ~= nil and not vim.tbl_isempty(note.metadata) then
    for k, v in pairs(note.metadata) do
      out[k] = v
    end
  end
  return out
end

return M
