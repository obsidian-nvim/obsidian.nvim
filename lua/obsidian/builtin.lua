---builtin functions that are default values for config options
local M = {}

---@class obsidian.link.LinkCreationOpts
---@field label? string
---@field path? string|?
---@field anchor? obsidian.note.HeaderAnchor|?
---@field block? obsidian.note.Block|?
---@field style? obsidian.link.LinkStyle
---@field format? obsidian.link.LinkFormat

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

  local path = tostring(opts.path or "")
  local label = tostring(opts.label or "")

  -- TODO: handle other extensions and suffixes, .canvas, .base
  local stem = path:gsub("%.md$", "")

  if label ~= "" and label ~= stem then
    return string.format("[[%s%s|%s%s]]", stem, anchor, label, header)
  end

  return string.format("[[%s%s]]", stem, anchor)
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

  local util = require "obsidian.util"
  local path = opts.path and util.urlencode(tostring(opts.path), { keep_path_sep = true }) or ""

  return string.format("[%s%s](%s%s)", opts.label, header, path, anchor)
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

---@param opts { insert: boolean|? }
M.resolve_attachment_func = function(opts)
  opts = opts or {}
  vim.ui.input({ prompt = "Url or filepath", completion = "file" }, function(input)
    if not input then
      require("obsidian.log").info "Aborted"
      return
    end
    input = vim.trim(input)
    local util = require "obsidian.util"
    local attachment = require "obsidian.attachment"
    local picker = require "obsidian.picker"
    local is_uri, scheme = util.is_uri(input)
    if is_uri and scheme and vim.startswith(scheme, "http") then
      attachment.add(input, true)
    else
      local path = vim.fs.normalize(input)
      local stat = vim.uv.fs_stat(path)
      if stat and stat.type == "directory" then
        picker.find_files {
          dir = path,
          callback = function(p)
            attachment.add(p, opts.insert)
          end,
        }
      else
        attachment.add(path, opts.insert)
      end
    end
  end)
end

return M
