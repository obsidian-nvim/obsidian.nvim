local util = require "obsidian.util"
local api = require "obsidian.api"
local attachment = require "obsidian.attachment"
local fs = require "obsidian.fs"
local Path = require "obsidian.path"

---@param abs_path string
---@param trash_dir string
---@param vault_root string
---@return string|?
local function trash_path(abs_path, trash_dir, vault_root)
  if util.is_subpath(abs_path, trash_dir) then
    return nil
  end

  local stat = vim.uv.fs_stat(abs_path)
  if not stat then
    return nil
  end

  local rel_path
  if util.is_subpath(abs_path, vault_root) then
    rel_path = assert(util.relpath(vault_root, abs_path))
  else
    rel_path = vim.fs.basename(abs_path)
  end

  local dest = fs.unique_path(vim.fs.joinpath(trash_dir, rel_path))
  if stat.type == "directory" then
    fs.copy_dir(abs_path, dest)
  else
    fs.mkdir(vim.fs.dirname(dest), { parents = true })
    vim.uv.fs_copyfile(abs_path, dest)
  end

  return dest
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
            attachment_result.deleted = fs.rm(resolved)
            result.attachments[#result.attachments + 1] = attachment_result
          end
        end
      end
    end
  end

  if opts.apply ~= false then
    result.deleted = fs.rm(abs_path)
  end

  return result
end

return M
