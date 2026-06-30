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
  "webm",
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
M.is_attachment_filetype = function(location)
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

--- Resolve a basename to full path inside the vault.
---
---@param src string
---@param bufnr_or_file integer|string|?
---@return string
M.resolve_attachment_path = function(src, bufnr_or_file)
  local Path = require "obsidian.path"
  local attachment_folder = Obsidian.opts.attachments.folder

  if vim.startswith(src, "file:/") then
    return vim.uri_to_fname(src)
  end

  ---@cast attachment_folder -nil
  if vim.startswith(attachment_folder, ".") then
    local path = type(bufnr_or_file) == "string" and bufnr_or_file or vim.api.nvim_buf_get_name(bufnr_or_file or 0)
    local dirname = Path.new(vim.fs.dirname(path))
    return tostring(dirname / attachment_folder / src)
  else
    return tostring(Obsidian.dir / attachment_folder / src)
  end
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

---@param dst string
---@return string|?
---@return string|?
local function resolve_declared_dst(dst)
  local Path = require "obsidian.path"
  dst = vim.trim(dst)
  if dst == "" then
    return nil, "Attachment destination cannot be empty"
  end

  local is_uri, scheme = util.is_uri(dst)
  if is_uri then
    if scheme ~= "file" then
      return nil, "Attachment destination must be a file path"
    end
    dst = vim.uri_to_fname(dst)
  end

  local dst_path = Path.new(dst)
  if not dst_path:is_absolute() then
    dst = tostring(Obsidian.dir / dst)
  end
  dst = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(dst), ":p"))

  local vault_dir = vim.fs.normalize(vim.fn.fnamemodify(tostring(Obsidian.dir), ":p"))
  if not util.is_subpath(dst, vault_dir) then
    return nil, "Attachment destination must be inside vault: " .. dst
  end

  return dst
end

---@param fname string
---@param bufnr integer|?
---@param dst string|?
---@return string|?
---@return string|?
local function resolve_dst(fname, bufnr, dst)
  if dst then
    return resolve_declared_dst(dst)
  end
  return M.resolve_attachment_path(fname, bufnr)
end

---@param src string
---@param bufnr integer|?
---@param dst string|?
---@return string|?
---@return string|?
local function get_attachment_paths(src, bufnr, dst)
  local is_uri, scheme = util.is_uri(src)
  if is_uri then
    if scheme == "file" then
      local src_path = vim.uri_to_fname(src)
      local fname = vim.fs.basename(src_path)
      if not fname or fname == "" then
        return nil, "Failed to resolve source filename from URI"
      end
      local resolved_dst, dst_err = resolve_dst(fname, bufnr, dst)
      if not resolved_dst then
        return nil, dst_err
      end
      return src_path, resolved_dst
    elseif scheme == "http" or scheme == "https" then
      local src_clean = src:gsub("#.*$", ""):gsub("%?.*$", "")
      local fname = src_clean:match "/([^/]+)$"
      if not fname or fname == "" then
        return nil, "Failed to resolve attachment name from URL"
      end
      local decoded_fname, err = decoded_basename(fname)
      if not decoded_fname then
        return nil, err
      end
      fname = decoded_fname
      local resolved_dst, dst_err = resolve_dst(fname, bufnr, dst)
      if not resolved_dst then
        return nil, dst_err
      end
      return src, resolved_dst
    else
      return nil, "Unsupported URI scheme '" .. tostring(scheme) .. "'"
    end
  end

  local src_path = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(src), ":p"))
  local fname = vim.fs.basename(src_path)
  if not fname or fname == "" then
    return nil, "Failed to resolve source filename from path"
  end

  local resolved_dst, dst_err = resolve_dst(fname, bufnr, dst)
  if not resolved_dst then
    return nil, dst_err
  end
  return src_path, resolved_dst
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

---@param src string
---@param opts { insert: boolean|?, bufnr: integer|?, dst: string|? }|?
---@return string|?
M.add = function(src, opts)
  opts = opts or {}
  src = vim.trim(src)
  local resolved_src, resolved_dst = get_attachment_paths(src, opts.bufnr, opts.dst)
  if not resolved_src then
    log.err(resolved_dst or "Failed to resolve attachment")
    return
  end

  ---@cast resolved_dst -nil
  if not opts.dst then
    resolved_dst = unique_dst(resolved_dst)
  end
  local err = copy_attachment(resolved_src, resolved_dst)
  if err then
    log.err(err)
    return
  end

  if opts.insert ~= false then
    local link_text = M.format_link(resolved_dst)
    local bufnr = opts.bufnr or 0
    vim.api.nvim_buf_call(bufnr, function()
      vim.api.nvim_put({ link_text }, "c", true, true)
    end)
  end

  return resolved_dst
end

---@param dst string
---@return string
M.format_link = function(dst)
  local basename = vim.fs.basename(dst)
  local style = Obsidian.opts.link.style
  if style == "wiki" then
    return "![[" .. basename .. "]]"
  elseif style == "markdown" then
    return "![](" .. util.urlencode(basename) .. ")"
  elseif type(style) == "function" then
    return style { path = basename }
  end
  return "![[" .. basename .. "]]"
end

return M
