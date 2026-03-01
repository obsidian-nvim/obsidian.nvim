---builtin functions that are default values for config options
local M = {}

---@class obsidian.link.LinkCreationOpts
---@field label? string
---@field path? obsidian.Path|string|?
---@field anchor? obsidian.note.HeaderAnchor|?
---@field block? obsidian.note.Block|?
---@field style? obsidian.link.LinkStyle
---@field format? obsidian.link.LinkFormat
---@field raw_path? obsidian.Path|string|?

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

  local path = tostring(opts.path)
  local raw_path = tostring(opts.raw_path or opts.path)
  local label = tostring(opts.label or "")
  local path_basename = vim.fs.basename(raw_path)

  if label ~= "" and label ~= path_basename then
    return string.format("[[%s%s|%s%s]]", path, anchor, label, header)
  end

  return string.format("[[%s%s]]", path, anchor)
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
---@return string|?
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
  if format_string[style] ~= nil then
    return string.format(format_string[style], name)
  elseif type(style) == "function" then
    return "!" .. style { path = path }
  end
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
