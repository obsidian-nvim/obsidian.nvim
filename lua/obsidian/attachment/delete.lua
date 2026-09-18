local M = {}

local attachment = require "obsidian.attachment"
local log = require "obsidian.log"

---@class obsidian.DeleteAttachmentOpts : obsidian.AttachmentResolveOpts

---@param err string
---@param callback? fun(err: string?, path: string?)
local function fail(err, callback)
  log.err(err)
  if callback then
    callback(err, nil)
  end
end

--- Delete an existing attachment.
---@param src string Attachment reference or path.
---@param opts obsidian.DeleteAttachmentOpts|?
---@param callback? fun(err: string?, path: string?)
function M.delete(src, opts, callback)
  if type(opts) == "function" then
    callback = opts
    opts = nil
  end

  attachment._resolve_async(src, opts, function(path, err)
    if not path then
      return fail(err or "Failed to resolve attachment", callback)
    end

    local ok, rm_err = pcall(vim.fs.rm, path)
    if not ok then
      return fail("Failed to delete attachment: " .. tostring(rm_err), callback)
    end

    if callback then
      callback(nil, path)
    end
  end)
end

return M
