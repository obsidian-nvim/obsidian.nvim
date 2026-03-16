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
M.is_attachment_path = function(location)
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
---@return string
M.resolve_attachment_path = function(src)
  local Path = require "obsidian.path"
  local attachment_folder = Obsidian.opts.attachments.folder

  if vim.startswith(src, "file:/") then
    return vim.uri_to_fname(src)
  end

  ---@cast attachment_folder -nil
  if vim.startswith(attachment_folder, ".") then
    local dirname = Path.new(vim.fs.dirname(vim.api.nvim_buf_get_name(0)))
    return tostring(dirname / attachment_folder / src)
  else
    return tostring(Obsidian.dir / attachment_folder / src)
  end
end

---@param src string
---@return string|?, string|?
local function get_attachment_paths(src)
  local is_uri, scheme = util.is_uri(src)
  if is_uri then
    if scheme == "file" then
      local src_path = vim.uri_to_fname(src)
      local fname = vim.fs.basename(src_path)
      if not fname or fname == "" then
        return nil, "Failed to resolve source filename from URI"
      end
      return src_path, util.resolve_attachment_path(fname)
    elseif scheme == "http" or scheme == "https" then
      local src_clean = src:gsub("#.*$", ""):gsub("%?.*$", "")
      local fname = src_clean:match "/([^/]+)$"
      if not fname or fname == "" then
        return nil, "Failed to resolve attachment name from URL"
      end
      return src, util.resolve_attachment_path(fname)
    else
      return nil, "Unsupported URI scheme '" .. tostring(scheme) .. "'"
    end
  end

  local src_path = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(src), ":p"))
  local fname = vim.fs.basename(src_path)
  if not fname or fname == "" then
    return nil, "Failed to resolve source filename from path"
  end

  return src_path, util.resolve_attachment_path(fname)
end

---@param src string
---@param dst string
---@return string|?
local function copy_attachment(src, dst)
  local is_uri, scheme = util.is_uri(src)

  vim.fn.mkdir(vim.fs.dirname(dst), "p")

  if is_uri and (scheme == "http" or scheme == "https") then
    if vim.fn.executable "curl" ~= 1 then
      return "Could not download URL: 'curl' is not installed"
    end

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

-- TODO: insert link?

---@param src string
---@return string|?
M.add = function(src)
  src = vim.trim(src)
  local resolved_src, resolved_dst_or_err = get_attachment_paths(src)
  if not resolved_src then
    log.err(assert(resolved_dst_or_err))
    return
  end

  local err = copy_attachment(resolved_src, assert(resolved_dst_or_err))
  if err then
    log.err(err)
    return
  end

  return resolved_dst_or_err
end

return M
