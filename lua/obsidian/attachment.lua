local M = {}
local util = require "obsidian.util"
local log = require "obsidian.log"

---@enum obsidian.attachment.ft
local filetypes = {
  -- markdown
  "md",
  -- json canvas
  "canvas",
  -- images
  "avif",
  "bmp",
  "gif",
  "jpg",
  "jpeg",
  "png",
  "svg",
  "webp",
  -- audio
  "flac",
  "m4a",
  "mp3",
  "ogg",
  "wav",
  "3gp",
  -- video
  "mkv",
  "mov",
  "mp4",
  "ogv",
  "webm",
  -- pdf
  "pdf",
}

-- TODO: file extension to mime type and vice versa

M.filetypes = filetypes

---Checks if a given string represents a valid attachment based on its suffix.
---
---@param location string
---@return boolean
M.is_attachment_path = function(location)
  location = location:lower()
  if vim.endswith(location, ".md") then
    return false
  end
  for _, ext in ipairs(filetypes) do
    if vim.endswith(location, "." .. ext) then
      return true
    end
  end
  return false
end

--- Resolve the configured destination for a new attachment.
---
--- The returned path does not need to exist.
---@param src string
---@param bufnr_or_filename integer|string|nil
---@return string
M.destination_path = function(src, bufnr_or_filename)
  local Path = require "obsidian.path"
  local attachment_folder = Obsidian.opts.attachments.folder

  if vim.startswith(src, "file:/") then
    return vim.uri_to_fname(src)
  end

  ---@cast attachment_folder -nil
  local fname = type(bufnr_or_filename) == "string" and bufnr_or_filename
    or vim.api.nvim_buf_get_name(bufnr_or_filename or 0)
  ---@cast fname -nil
  if vim.startswith(attachment_folder, ".") then
    ---TODO: verify is obsidian buffer
    local dirname = Path.new(vim.fs.dirname(fname))
    return tostring(dirname / attachment_folder / src)
  else
    local workspace_dir = require("obsidian.api").resolve_workspace_dir(fname ~= "" and fname or nil)
    return tostring(workspace_dir / attachment_folder / src)
  end
end

--- Compatibility alias for `destination_path`.
M.resolve_attachment_path = M.destination_path

---@class obsidian.AttachmentResolveOpts
---@field bufnr? integer Buffer containing the attachment reference.
---@field filename? string File containing the attachment reference.

---@class obsidian.AttachmentMatch
---@field path string Absolute attachment path.
---@field rel_path string Vault-relative attachment path.
---@field basename string Attachment basename.
---@field ambiguous boolean Whether another match has the same basename.

---@param opts obsidian.AttachmentResolveOpts|?
---@return string filename
---@return string workspace_dir
---@return string source_dir
local function resolve_context(opts)
  opts = opts or {}
  local filename = opts.filename
  if not filename then
    filename = vim.api.nvim_buf_get_name(opts.bufnr or 0)
  end
  local workspace_dir = tostring(require("obsidian.api").resolve_workspace_dir(filename ~= "" and filename or nil))
  local source_dir = filename ~= "" and vim.fs.dirname(filename) or workspace_dir
  return filename, workspace_dir, source_dir
end

---@param path string
---@return boolean
local function is_attachment_file(path)
  local stat = vim.uv.fs_stat(path)
  return stat ~= nil and stat.type == "file" and M.is_attachment_path(path)
end

---@param path string
---@param base string
---@return string?
local function relative_path(path, base)
  local ok, relative = pcall(function()
    return require("obsidian.path").new(path):relative_to(base)
  end)
  return ok and tostring(relative):gsub("^%./", "") or nil
end

---@param value string
---@return string
local function comparable_path(value)
  return vim.fs.normalize(value):gsub("^%./", ""):gsub("\\", "/"):lower()
end

---@param paths string[]
---@return string[]
local function unique_paths(paths)
  local result = {}
  local seen = {}
  for _, path in ipairs(paths) do
    path = vim.fs.normalize(path)
    if not seen[path] then
      seen[path] = true
      result[#result + 1] = path
    end
  end
  return result
end

--- Find attachments in the source workspace.
---
--- Private for now; completion and attachment operations may use it internally.
---@param term string
---@param opts obsidian.AttachmentResolveOpts|?
---@param callback fun(matches: obsidian.AttachmentMatch[])
---@return fun() cancel
M._find_async = function(term, opts, callback)
  local _, workspace_dir = resolve_context(opts)
  local matches = {}

  return require("obsidian.search").find_async(workspace_dir, term, { include_non_markdown = true }, function(path)
    if M.is_attachment_path(path) then
      matches[#matches + 1] = {
        path = path,
        rel_path = relative_path(path, workspace_dir) or path,
        basename = vim.fs.basename(path),
        ambiguous = false,
      }
    end
  end, function()
    local basename_counts = {}
    for _, match in ipairs(matches) do
      local basename = match.basename:lower()
      basename_counts[basename] = (basename_counts[basename] or 0) + 1
    end
    for _, match in ipairs(matches) do
      match.ambiguous = basename_counts[match.basename:lower()] > 1
    end
    table.sort(matches, function(a, b)
      local a_name, b_name = a.basename:lower(), b.basename:lower()
      if a_name == b_name then
        return a.rel_path:lower() < b.rel_path:lower()
      end
      return a_name < b_name
    end)
    vim.schedule(function()
      callback(matches)
    end)
  end)
end

---@param src string
---@return string?
local function normalize_reference(src)
  src = vim.trim(src)
  src = util.strip_block_links(src)
  src = util.strip_anchor_links(src)
  src = vim.uri_decode(src) or src
  return src ~= "" and src or nil
end

---@param src string
---@param opts obsidian.AttachmentResolveOpts|?
---@param matches obsidian.AttachmentMatch[]|nil
---@return string? path
---@return string? err
---@return string[]? candidates
M._resolve_reference = function(src, opts, matches)
  local Path = require "obsidian.path"
  local normalized = normalize_reference(src)
  if not normalized then
    return nil, "Invalid attachment reference"
  end

  local is_uri, scheme = util.is_uri(normalized)
  if is_uri then
    if scheme ~= "file" then
      return nil, "Unsupported attachment URI scheme '" .. tostring(scheme) .. "'"
    end
    local uri_path = vim.fs.normalize(vim.uri_to_fname(normalized))
    if is_attachment_file(uri_path) then
      return uri_path
    end
    return nil, "Attachment not found: " .. uri_path
  end

  local _, workspace_dir, source_dir = resolve_context(opts)
  local path = Path.new(normalized)
  if path:is_absolute() and is_attachment_file(normalized) then
    return vim.fs.normalize(normalized)
  end

  local has_path = normalized:find "[/\\]" ~= nil
  if not has_path then
    local configured = vim.fs.normalize(M.destination_path(normalized, opts and (opts.filename or opts.bufnr) or nil))
    if is_attachment_file(configured) then
      return configured
    end
  end

  local direct = {}
  if has_path then
    if vim.startswith(normalized, "./") or vim.startswith(normalized, "../") then
      direct[#direct + 1] = vim.fs.joinpath(source_dir, normalized)
    elseif vim.startswith(normalized, "/") then
      direct[#direct + 1] = vim.fs.joinpath(workspace_dir, normalized:sub(2))
    else
      direct[#direct + 1] = vim.fs.joinpath(source_dir, normalized)
      direct[#direct + 1] = vim.fs.joinpath(workspace_dir, normalized)
    end
  end

  local candidates = {}
  for _, candidate in ipairs(unique_paths(direct)) do
    if is_attachment_file(candidate) then
      candidates[#candidates + 1] = candidate
    end
  end

  if matches then
    local target = comparable_path(normalized:gsub("^/", ""))
    for _, match in ipairs(matches) do
      if is_attachment_file(match.path) then
        local matches_reference
        if has_path then
          local from_workspace = comparable_path(match.rel_path)
          local from_source = relative_path(match.path, source_dir)
          matches_reference = from_workspace == target
            or (from_source ~= nil and comparable_path(from_source) == comparable_path(normalized))
        else
          matches_reference = match.basename:lower() == normalized:lower()
        end
        if matches_reference then
          candidates[#candidates + 1] = match.path
        end
      end
    end
  end

  candidates = unique_paths(candidates)
  if #candidates == 1 then
    return candidates[1]
  elseif #candidates > 1 then
    return nil, "Ambiguous attachment reference '" .. src .. "'", candidates
  elseif matches then
    return nil, "Attachment not found: " .. src
  end
end

--- Resolve an existing attachment reference.
---
--- Private for now; mutation and navigation operations should use this instead
--- of treating the configured destination as an existing file.
---@param src string
---@param opts obsidian.AttachmentResolveOpts|?
---@param callback fun(path: string?, err: string?, candidates: string[]?)
---@return fun() cancel
M._resolve_async = function(src, opts, callback)
  local path, err, candidates = M._resolve_reference(src, opts, nil)
  if path or err then
    vim.schedule(function()
      callback(path, err, candidates)
    end)
    return function() end
  end

  local normalized = assert(normalize_reference(src))
  return M._find_async(vim.fs.basename(normalized), opts, function(matches)
    path, err, candidates = M._resolve_reference(src, opts, matches)
    callback(path, err, candidates)
  end)
end

---@param src string
---@param opts obsidian.AttachmentResolveOpts|?
---@return string? path
---@return string? err
---@return string[]? candidates
M._resolve = function(src, opts)
  opts = opts or {}
  local result = require("obsidian.async").block_on(function(cb)
    M._resolve_async(src, {}, cb)
  end, 1000)
  return result or {}
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

  return src_path, M.destination_path(fname, bufnr)
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
    local link_text = M.format_link(resolved_dst, { bufnr = bufnr })
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

---@class obsidian.AttachmentLinkOpts : obsidian.AttachmentResolveOpts
---@field embed? boolean Prefix the link with `!`.
---@field format? obsidian.link.LinkFormat
---@field label? string
---@field style? obsidian.link.LinkStyleOption

---@param dst string
---@param format obsidian.link.LinkFormat
---@param opts obsidian.AttachmentLinkOpts
---@return string
local function format_path(dst, format, opts)
  if format == "absolute" then
    return assert(require("obsidian.path").new(dst):vault_relative_path { strict = true })
  elseif format == "relative" then
    local _, _, source_dir = resolve_context(opts)
    local rel_path = assert(util.relpath(source_dir, dst), "failed to resolve attachment path against source file")
    return (rel_path:gsub("^%./", ""))
  end
  return vim.fs.basename(dst)
end

--- Format a reference to an attachment.
---@param dst string
---@param opts obsidian.AttachmentLinkOpts|?
---@return string
M.format_reference = function(dst, opts)
  opts = opts or {}
  local format = opts.format or Obsidian.opts.link.format
  ---@cast format -nil
  local style = opts.style or Obsidian.opts.link.style
  local path = format_path(dst, format, opts)
  local link_opts = {
    path = path,
    label = opts.label or "",
    style = style,
    format = format,
  }
  local link

  if style == "wiki" or style == nil then
    link = require("obsidian.builtin").wiki_link(link_opts)
  elseif style == "markdown" then
    link = require("obsidian.builtin").markdown_link(link_opts)
  elseif type(style) == "function" then
    link = style(link_opts)
  else
    error(string.format("Invalid link style '%s'", style))
  end

  if opts.embed and not vim.startswith(link, "!") then
    link = "!" .. link
  end
  return link
end

--- Format an embedded attachment link.
---@param dst string
---@param opts obsidian.AttachmentLinkOpts|?
---@return string
M.format_link = function(dst, opts)
  opts = vim.tbl_extend("force", opts or {}, { embed = true })
  return M.format_reference(dst, opts)
end

--- Rename an attachment and update references that resolve to it.
---@param src string Attachment reference or path.
---@param new_name string New basename. The old extension is retained when omitted.
---@param opts obsidian.RenameAttachmentOpts|?
---@param callback? fun(err: string?, edit: lsp.WorkspaceEdit?, meta: obsidian.RenameAttachmentMeta?)
M.rename = function(src, new_name, opts, callback)
  return require("obsidian.attachment.rename").rename(src, new_name, opts, callback)
end

--- Delete an existing attachment.
---@param src string Attachment reference or path.
---@param opts obsidian.DeleteAttachmentOpts|?
---@param callback? fun(err: string?, path: string?)
M.delete = function(src, opts, callback)
  return require("obsidian.attachment.delete").delete(src, opts, callback)
end

return M
