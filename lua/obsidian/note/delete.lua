local util = require "obsidian.util"
local api = require "obsidian.api"
local attachment = require "obsidian.attachment"
local Path = require "obsidian.path"

---@param path string
---@param dir string
---@return boolean
local function path_is_in_dir(path, dir)
  return path == dir or vim.startswith(path, dir .. "/")
end

---@param path string
---@return string
local function unique_path(path)
  if not vim.uv.fs_stat(path) then
    return path
  end

  local parent = vim.fs.dirname(path)
  local basename = vim.fs.basename(path)
  local stem, ext = basename:match "^(.*)%.([^%.]+)$"
  if stem and stem ~= "" then
    ext = "." .. ext
  else
    stem = basename
    ext = ""
  end

  for i = 1, 1000 do
    local candidate = vim.fs.joinpath(parent, ("%s-%d%s"):format(stem, i, ext))
    if not vim.uv.fs_stat(candidate) then
      return candidate
    end
  end

  error("failed to find unique path for " .. path)
end

---@param src string
---@param dest string
local function copy_dir(src, dest)
  vim.fn.mkdir(dest, "p")
  local handle = vim.uv.fs_scandir(src)
  if not handle then
    return
  end

  while true do
    local name, typ = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end

    local src_child = vim.fs.joinpath(src, name)
    local dest_child = vim.fs.joinpath(dest, name)
    if typ == "directory" then
      copy_dir(src_child, dest_child)
    else
      vim.fn.mkdir(vim.fs.dirname(dest_child), "p")
      vim.uv.fs_copyfile(src_child, dest_child)
    end
  end
end

---@param abs_path string
---@param trash_dir string
---@param vault_root string
---@return string|?
local function trash_path(abs_path, trash_dir, vault_root)
  if path_is_in_dir(abs_path, trash_dir) then
    return nil
  end

  local stat = vim.uv.fs_stat(abs_path)
  if not stat then
    return nil
  end

  local rel_path
  if path_is_in_dir(abs_path, vault_root) then
    rel_path = abs_path:sub(#vault_root + 2)
  else
    rel_path = vim.fs.basename(abs_path)
  end

  local dest = unique_path(vim.fs.joinpath(trash_dir, rel_path))
  if stat.type == "directory" then
    copy_dir(abs_path, dest)
  else
    vim.fn.mkdir(vim.fs.dirname(dest), "p")
    vim.uv.fs_copyfile(abs_path, dest)
  end

  return dest
end

---@param path string
---@return boolean
local function delete_path(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return false
  end
  return vim.fn.delete(path, stat.type == "directory" and "rf" or "") == 0
end

local M = {}

--- Delete this note.
---
--- Set `opts.apply = false` when another caller, like a file browser, will
--- delete the note file but should still run Obsidian's delete flow.
---
---@param opts obsidian.note.DeleteOpts|?
---@return obsidian.note.DeleteResult
M.delete = function(self, opts)
  opts = opts or {}

  local path = assert(self.path, "note has no path")
  local abs_path = tostring(Path.new(path):resolve())
  local vault_root = tostring(Obsidian.dir)
  local trash = opts.trash
  if trash == nil and Obsidian.opts.file then
    trash = Obsidian.opts.file.trash
  end

  local result = {
    deleted = false,
    cancelled = false,
    trashed_path = nil,
    attachments = {},
  }

  if opts.confirm_backlinks ~= false then
    local matches = self:backlinks()
    if matches and #matches > 0 then
      local prompt = ("'%s' is referenced in %d place(s). Delete anyway?"):format(self:display_name(), #matches)
      if api.confirm(prompt) ~= "Yes" then
        result.cancelled = true
        return result
      end
    end
  end

  if trash == "local" then
    result.trashed_path = trash_path(abs_path, tostring(Obsidian.dir / ".trash"), vault_root)
  end

  if opts.confirm_attachments ~= false then
    for _, link in ipairs(self:links()) do
      local loc = util.parse_link(link.link)
      if loc and attachment.is_attachment_path(loc) then
        local resolved = attachment.resolve_attachment_path(loc, abs_path)
        if resolved and vim.uv.fs_stat(resolved) then
          local prompt = ("Note contains attachment '%s'. Delete it too?"):format(vim.fs.basename(resolved))
          if api.confirm(prompt) == "Yes" then
            local attachment_result = {
              path = resolved,
              deleted = false,
              trashed_path = nil,
            }
            if trash == "local" then
              attachment_result.trashed_path = trash_path(resolved, tostring(Obsidian.dir / ".trash"), vault_root)
            end
            attachment_result.deleted = delete_path(resolved)
            result.attachments[#result.attachments + 1] = attachment_result
          end
        end
      end
    end
  end

  if opts.apply ~= false then
    result.deleted = delete_path(abs_path)
  end

  return result
end

return M
