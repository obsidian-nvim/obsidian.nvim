local M = {}
local util = require "obsidian.util"
local log = require "obsidian.log"
local filetypes = require "obsidian.filetypes"

---@enum obsidian.attachment.ft
local legacy_filetypes = {
  -- markdown
  "md",
}
vim.list_extend(legacy_filetypes, filetypes.attachment_extensions)

-- TODO: file extension to mime type and vice versa

M.filetypes = legacy_filetypes
M.extensions = filetypes.attachment_extensions

---Checks if a given string represents a valid attachment based on its suffix.
---
---@param location string
---@return boolean
M.is_attachment_path = function(location)
  return filetypes.is_attachment(location)
end

---@param src string
---@param bufnr integer|?
---@return string
local function configured_attachment_path(src, bufnr)
  local Path = require "obsidian.path"
  local attachment_folder = Obsidian.opts.attachments.folder
  bufnr = bufnr or 0
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local current_dir = bufname ~= "" and vim.fs.dirname(bufname) or nil

  ---@cast attachment_folder -nil
  if vim.startswith(attachment_folder, ".") then
    local dirname = Path.new(current_dir or tostring(Obsidian.dir))
    return vim.fs.normalize(tostring(dirname / attachment_folder / src))
  end
  return vim.fs.normalize(tostring(Obsidian.dir / attachment_folder / src))
end

--- Resolve an attachment reference to a full path inside the vault.
---
---@param src string
---@param bufnr integer|?
---@return string
M.resolve_attachment_path = function(src, bufnr)
  if vim.startswith(src, "file:/") then
    return vim.uri_to_fname(src)
  end

  src = vim.uri_decode(src) or src
  ---@cast src string
  if require("obsidian.path").new(src):is_absolute() then
    return vim.fs.normalize(src)
  end

  bufnr = bufnr or 0
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local current_dir = bufname ~= "" and vim.fs.dirname(bufname) or nil

  local candidates = {}
  if current_dir then
    candidates[#candidates + 1] = vim.fs.joinpath(current_dir, src)
  end
  candidates[#candidates + 1] = vim.fs.joinpath(tostring(Obsidian.dir), src)
  candidates[#candidates + 1] = configured_attachment_path(src, bufnr)

  for _, candidate in ipairs(candidates) do
    candidate = vim.fs.normalize(candidate)
    if vim.uv.fs_stat(candidate) then
      return candidate
    end
  end

  -- Preserve the historical behavior for callers resolving a destination that
  -- does not exist yet, such as attachment.add().
  return configured_attachment_path(src, bufnr)
end

---@param fname string
---@return string|?
---@return string|?
local function decoded_basename(fname)
  local decoded = vim.uri_decode(fname)
  local basename = vim.fs.basename(decoded:gsub("\\", "/"))
  if not basename or basename == "" or basename == "." or basename == ".." then
    return nil, "Failed to resolve attachment name from URL"
  end
  return basename
end

---@param name string
---@return string|?
---@return string|?
local function validate_attachment_name(name)
  name = vim.trim(name)
  if name == "" or name == "." or name == ".." then
    return nil, "Invalid attachment name"
  elseif name:find "[/\\]" then
    return nil, "Attachment name must be a basename"
  end
  return name
end

---@param src string
---@param bufnr integer|?
---@param new_name string|?
---@return string|?
---@return string|?
local function get_attachment_paths(src, bufnr, new_name)
  local is_uri, scheme = util.is_uri(src)
  local src_path, fname

  if is_uri then
    if scheme == "file" then
      src_path = vim.uri_to_fname(src)
      fname = vim.fs.basename(src_path)
      if not fname or fname == "" then
        return nil, "Failed to resolve source filename from URI"
      end
    elseif scheme == "http" or scheme == "https" then
      local src_clean = src:gsub("#.*$", ""):gsub("%?.*$", "")
      fname = src_clean:match "/([^/]+)$"
      if not fname or fname == "" then
        return nil, "Failed to resolve attachment name from URL"
      end
      local decoded_fname, err = decoded_basename(fname)
      if not decoded_fname then
        return nil, err
      end
      src_path = src
      fname = decoded_fname
    else
      return nil, "Unsupported URI scheme '" .. tostring(scheme) .. "'"
    end
  else
    local expanded = vim.fn.expand(src) --[[@as string]]
    src_path = vim.fs.normalize(vim.fn.fnamemodify(expanded, ":p"))
    fname = vim.fs.basename(src_path)
    if not fname or fname == "" then
      return nil, "Failed to resolve source filename from path"
    end
  end

  if new_name then
    local validated_name, err = validate_attachment_name(new_name)
    if not validated_name then
      return nil, err
    end
    fname = validated_name
  end

  return src_path, configured_attachment_path(fname, bufnr)
end

---@param src string
---@param dst string
---@return string|?
local function copy_attachment(src, dst)
  local is_uri, scheme = util.is_uri(src)

  local mkdir_ok, mkdir_err = pcall(vim.fn.mkdir, vim.fs.dirname(dst), "p")
  if not mkdir_ok then
    return "Failed to create attachment directory: " .. tostring(mkdir_err)
  end

  if is_uri and (scheme == "http" or scheme == "https") then
    if vim.fn.executable "curl" ~= 1 then
      return "Could not download URL: 'curl' is not installed"
    end

    -- TODO: make async once vim.spinner lands
    local obj = vim.system({ "curl", "-fL", src, "-o", dst }, { text = true }):wait()
    if obj.code ~= 0 then
      return "Failed to download attachment: " .. (obj.stderr or obj.stdout or "unknown error")
    end
    return nil
  end

  local ok, err = vim.uv.fs_copyfile(src, dst)
  if not ok then
    return "Failed to copy attachment: " .. tostring(err)
  end
end

---@param dst string
---@return string
local function unique_dst(dst)
  if not vim.uv.fs_stat(dst) then
    return dst
  end
  local dir = vim.fs.dirname(dst)
  local base = vim.fs.basename(dst)
  local stem, ext = base:match "^(.+)(%.[^.]+)$"
  if not stem then
    stem, ext = base, ""
  end
  for i = 1, 9999 do
    local candidate = string.format("%s/%s (%d)%s", dir, stem, i, ext)
    if not vim.uv.fs_stat(candidate) then
      return candidate
    end
  end
  return dst
end

---@class obsidian.AttachmentPosition
---@field row integer 1-indexed row.
---@field col integer 0-indexed column.

---@class obsidian.AddAttachmentContext
---@field scope string Context where the attachment was added.
---@field buffer integer Buffer associated with the action.
---@field bufnr integer Deprecated alias for `buffer`.

---@class obsidian.AddAttachmentOpts
---@field insert? boolean Insert the generated attachment link. Defaults to true.
---@field bufnr? integer Buffer used for relative attachment resolution and link insertion. Defaults to current buffer.
---@field new_name? string Destination attachment basename. Path separators are rejected.
---@field position? obsidian.AttachmentPosition|integer[] Exact position where the link should be inserted.
---@field scope? string Context where the attachment is added.

---@param pos obsidian.AttachmentPosition|integer[]|?
---@return obsidian.AttachmentPosition|?
local function normalize_position(pos)
  if not pos then
    return nil
  elseif pos.row and pos.col then
    return { row = pos.row, col = pos.col }
  elseif pos[1] and pos[2] then
    return { row = pos[1], col = pos[2] }
  end
end

---@param path string
---@param ctx obsidian.AddAttachmentContext
local function fire_add_attachment(path, ctx)
  util.fire_callback("add_attachment", Obsidian.opts.callbacks.add_attachment, path, ctx)
  vim.api.nvim_exec_autocmds("User", {
    pattern = "ObsidianAttachmentAdded",
    data = { path = path, ctx = ctx },
  })
end

---@param src string
---@param opts obsidian.AddAttachmentOpts|?
---@return string|?
M.add = function(src, opts)
  opts = opts or {}
  src = vim.trim(src)
  local resolved_src, resolved_dst = get_attachment_paths(src, opts.bufnr, opts.new_name)
  if not resolved_src then
    log.err(resolved_dst or "Failed to resolve attachment")
    return
  end

  ---@cast resolved_dst -nil
  resolved_dst = unique_dst(resolved_dst)
  local err = copy_attachment(resolved_src, resolved_dst)
  if err then
    log.err(err)
    return
  end

  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end

  if opts.insert ~= false then
    local link_text = M.format_link(resolved_dst)
    local insert_pos = normalize_position(opts.position)
    if insert_pos then
      vim.api.nvim_buf_set_text(
        bufnr,
        insert_pos.row - 1,
        insert_pos.col,
        insert_pos.row - 1,
        insert_pos.col,
        { link_text }
      )
    else
      vim.api.nvim_buf_call(bufnr, function()
        vim.api.nvim_put({ link_text }, "c", true, true)
      end)
    end
  end

  fire_add_attachment(resolved_dst, {
    scope = opts.scope or "attachment.add",
    buffer = bufnr,
    bufnr = bufnr,
  })

  return resolved_dst
end

---@class obsidian.AttachmentMatch
---@field path string
---@field rel_path string
---@field basename string
---@field ambiguous boolean

---Find attachments from the active vault cache.
---
---This intentionally has no filesystem/ripgrep fallback yet. When the cache is
---disabled, the callback receives an empty list.
---@param term string
---@param callback fun(matches: obsidian.AttachmentMatch[])
function M.find_async(term, callback)
  local cache = require "obsidian.cache"
  if not cache.is_enabled() then
    callback {}
    return
  end

  cache.when_ready(function()
    if not cache.is_enabled() then
      callback {}
      return
    end

    local query = string.lower(vim.trim(term))
    local rows = cache.attachments.all()
    local basename_counts = {}
    for path in pairs(rows) do
      local basename = cache.attachments.basename(path)
      local key = string.lower(basename)
      basename_counts[key] = (basename_counts[key] or 0) + 1
    end

    ---@type obsidian.AttachmentMatch[]
    local matches = {}
    for path in pairs(rows) do
      local basename = cache.attachments.basename(path)
      local rel_path = cache.attachments.rel_path(path)
      if
        query == ""
        or string.find(string.lower(basename), query, 1, true)
        or string.find(string.lower(rel_path), query, 1, true)
      then
        matches[#matches + 1] = {
          path = path,
          rel_path = rel_path,
          basename = basename,
          ambiguous = basename_counts[string.lower(basename)] > 1,
        }
      end
    end

    table.sort(matches, function(a, b)
      local a_name, b_name = string.lower(a.basename), string.lower(b.basename)
      if a_name == b_name then
        return string.lower(a.rel_path) < string.lower(b.rel_path)
      end
      return a_name < b_name
    end)
    callback(matches)
  end)
end

---@class obsidian.AttachmentLinkOpts
---@field bufnr? integer
---@field embed? boolean
---@field format? obsidian.link.LinkFormat
---@field label? string
---@field style? obsidian.link.LinkStyle

---@param dst string
---@param format obsidian.link.LinkFormat
---@param bufnr integer
---@return string
local function format_path(dst, format, bufnr)
  if format == "absolute" then
    local Path = require "obsidian.path"
    return assert(Path.new(dst):vault_relative_path { strict = true })
  elseif format == "relative" then
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    local base_dir = bufname ~= "" and vim.fs.dirname(bufname) or tostring(Obsidian.dir)
    local rel_path = util.relpath(base_dir, dst)
    assert(rel_path, "failed to resolve attachment path against current note")
    return rel_path
  end
  return vim.fs.basename(dst)
end

---Format a reference to an existing attachment.
---@param dst string
---@param opts obsidian.AttachmentLinkOpts?
---@return string
function M.format_reference(dst, opts)
  opts = opts or {}
  local bufnr = opts.bufnr or 0
  local format = opts.format or Obsidian.opts.link.format
  ---@cast format obsidian.link.LinkFormat
  local style = opts.style or Obsidian.opts.link.style
  local path = format_path(dst, format, bufnr)
  local label = opts.label or ""
  local link

  if style == "wiki" or style == nil then
    link = require("obsidian.builtin").wiki_link { path = path, label = label }
  elseif style == "markdown" then
    link = require("obsidian.builtin").markdown_link { path = path, label = label }
  elseif type(style) == "function" then
    link = style {
      path = path,
      label = label,
      style = style,
      format = format,
    }
  else
    error(string.format("Invalid link style '%s'", style))
  end

  if opts.embed and not vim.startswith(link, "!") then
    link = "!" .. link
  end
  return link
end

---@param dst string
---@return string
M.format_link = function(dst)
  return M.format_reference(dst, { embed = true, format = "shortest" })
end

return M
