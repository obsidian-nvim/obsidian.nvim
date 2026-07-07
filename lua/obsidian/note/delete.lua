local util = require "obsidian.util"
local api = require "obsidian.api"
local attachment = require "obsidian.attachment"
local Path = require "obsidian.path"

local M = {}

---@param path string
---@return boolean
local function rm(path)
  if not vim.uv.fs_lstat(path) then
    return false
  end

  return pcall(vim.fs.rm, path, { recursive = true })
end

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

  local result = {
    deleted = false,
    cancelled = false,
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
              deleted = rm(resolved),
            }
            result.attachments[#result.attachments + 1] = attachment_result
          end
        end
      end
    end
  end

  if opts.apply ~= false then
    result.deleted = rm(abs_path)
  end

  return result
end

return M
