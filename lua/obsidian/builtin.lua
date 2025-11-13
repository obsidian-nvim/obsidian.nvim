---builtin functions that are default values for config options
local M = {}
local util = require "obsidian.util"

---@class obsidian.link.LinkCreationOpts
---@field label string
---@field path? obsidian.Path|string|?
---@field id? string|integer|?
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

---Create a UTF-8 slug-based ID from title.
---Falls back to `zettel_id()` when title is empty or cannot be slugified.
---
---@param title string|?
---@return string
M.title_to_slug = function(title)
  if type(title) ~= "string" then
    return M.zettel_id()
  end

  local slug = vim.trim(vim.fn.tolower(title))
  if slug == "" then
    return M.zettel_id()
  end

  slug = vim.fn.substitute(slug, "[^[:keyword:][:space:]-]", "", "g")
  slug = vim.fn.substitute(slug, "[_[:space:]]\\+", "-", "g")
  slug = vim.fn.substitute(slug, "-\\+", "-", "g")
  slug = vim.fn.substitute(slug, "^-\\+", "", "")
  slug = vim.fn.substitute(slug, "-\\+$", "", "")

  if slug == "" then
    return M.zettel_id()
  end

  return slug
end

---Create a UTF-8 slug-based note ID from title.
---When a target directory is provided, appends `-2`, `-3`, ... to avoid collisions.
---
---@param title string|?
---@param dir obsidian.Path|?
---@return string
M.title_id = function(title, dir)
  local base = M.title_to_slug(title)

  if not dir then
    return base
  end

  local Path = require "obsidian.path"
  local base_dir = Path.new(dir)
  local candidate = base
  local idx = 2

  while (base_dir / candidate):with_suffix(".md", true):exists() do
    candidate = string.format("%s-%d", base, idx)
    idx = idx + 1
  end

  return candidate
end

---@param opts obsidian.link.LinkCreationOpts
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

---NOTE: more close to what should be default
---@param opts obsidian.link.LinkCreationOpts
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

---@param opts obsidian.link.LinkCreationOpts
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

---@param opts obsidian.link.LinkCreationOpts
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

---@param opts obsidian.link.LinkCreationOpts
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
