---builtin functions that are default values for config options
local M = {}
local util = require "obsidian.util"

---Create a new unique Zettel ID.
---
---@param title string|? The title for the note
---@return string
M.zettel_id = function(title)
  local timestamp = os.date "%Y%m%d%H%M"
  local suffix = ""
  if title ~= nil and title ~= "" then
    suffix = "-" .. title:gsub(" ", "-"):gsub("[^A-Za-z0-9-]", ""):lower()
  end
  return timestamp .. suffix
end

---@param opts { path: string, label: string, id: string|integer|?, anchor: obsidian.note.HeaderAnchor|?, block: obsidian.note.Block|? }
---@return string
M.wiki_link_alias_only = function(opts)
  ---@type string
  local header_or_block = ""
  if opts.anchor then
    header_or_block = string.format("#%s", opts.anchor.header)
  elseif opts.block then
    header_or_block = string.format("#%s", opts.block.id)
  end
  return string.format("[[%s%s]]", opts.label, header_or_block)
end

---@param opts { path: string, label: string, id: string|integer|?, anchor: obsidian.note.HeaderAnchor|?, block: obsidian.note.Block|? }
---@return string
M.wiki_link_path_only = function(opts)
  ---@type string
  local header_or_block = ""
  if opts.anchor then
    header_or_block = opts.anchor.anchor
  elseif opts.block then
    header_or_block = string.format("#%s", opts.block.id)
  end
  return string.format("[[%s%s]]", opts.path, header_or_block)
end

---@param opts { path: string, label: string, id: string|integer|?, anchor: obsidian.note.HeaderAnchor|?, block: obsidian.note.Block|? }
---@return string
M.wiki_link_path_prefix = function(opts)
  local anchor = ""
  local header = ""
  if opts.anchor then
    anchor = opts.anchor.anchor
    header = util.format_anchor_label(opts.anchor)
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

---@param opts { path: string, label: string, id: string|integer|?, anchor: obsidian.note.HeaderAnchor|?, block: obsidian.note.Block|? }
---@return string
M.wiki_link_id_prefix = function(opts)
  local anchor = ""
  local header = ""
  if opts.anchor then
    anchor = opts.anchor.anchor
    header = util.format_anchor_label(opts.anchor)
  elseif opts.block then
    anchor = "#" .. opts.block.id
    header = "#" .. opts.block.id
  end

  if opts.id == nil then
    return string.format("[[%s%s]]", opts.label, anchor)
  elseif opts.label ~= opts.id then
    return string.format("[[%s%s|%s%s]]", opts.id, anchor, opts.label, header)
  else
    return string.format("[[%s%s]]", opts.id, anchor)
  end
end

---@param opts { path: string, label: string, id: string|integer|?, anchor: obsidian.note.HeaderAnchor|?, block: obsidian.note.Block|? }
---@return string
M.markdown_link = function(opts)
  local anchor = ""
  local header = ""
  if opts.anchor then
    anchor = opts.anchor.anchor
    header = util.format_anchor_label(opts.anchor)
  elseif opts.block then
    anchor = "#" .. opts.block.id
    header = "#" .. opts.block.id
  end

  local path = util.urlencode(opts.path, { keep_path_sep = true })
  return string.format("[%s%s](%s%s)", opts.label, header, path, anchor)
end

---@param path string
---@return string
M.img_text_func = function(path)
  local format_string = {
    markdown = "![](%s)",
    wiki = "![[%s]]",
  }
  local style = Obsidian.opts.preferred_link_style
  local name = vim.fs.basename(tostring(path))

  if style == "markdown" then
    name = require("obsidian.util").urlencode(name)
  end

  return string.format(format_string[style], name)
end

M.frontmatter = function(self)
  local out = { id = self.id, aliases = self.aliases, tags = self.tags }
  if self.metadata ~= nil and not vim.tbl_isempty(self.metadata) then
    for k, v in pairs(self.metadata) do
      out[k] = v
    end
  end
  return out
end

return M
