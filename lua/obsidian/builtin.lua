local M = {}
local api = require "obsidian.api"
local util = require "obsidian.util"

---builtin functions that are default values for actions, and modules

M.smart_action = function()
  local legacy = Obsidian.opts.legacy_commands
  -- follow link if possible
  if api.cursor_link() then
    return legacy and "<cmd>ObsidianFollowLink<cr>" or "<cmd>Obsidian follow_link<cr>"
  end

  -- show notes with tag if possible
  if api.cursor_tag() then
    return legacy and "<cmd>ObsidianTags<cr>" or "<cmd>Obsidian tags<cr>"
  end

  if api.cursor_heading() then
    return "za"
  end

  -- toggle task if possible
  -- cycles through your custom UI checkboxes, default: [ ] [~] [>] [x]
  return legacy and "<cmd>ObsidianToggleCheckbox<cr>" or "<cmd>Obsidian toggle_checkbox<cr>"
end

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

return M
