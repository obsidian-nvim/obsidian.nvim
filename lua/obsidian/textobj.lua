local M = {}
local api = require "obsidian.api"

---@param row integer 1-indexed
---@param start_col integer 1-indexed inclusive
---@param finish_col integer 1-indexed inclusive
---@param replacement string
local function replace(row, start_col, finish_col, replacement)
  vim.api.nvim_buf_set_text(0, row - 1, start_col - 1, row - 1, finish_col, { replacement })
end

---@param target string
local function maybe_delete_attachment(target)
  local attachment = require "obsidian.attachment"
  if not attachment.is_attachment_path(target) then
    return
  end
  attachment._resolve_async(target, {}, function(path)
    if not path then
      return
    end
    if vim.fn.filereadable(path) ~= 1 then
      return
    end
    local choice = vim.fn.confirm("Delete attachment file?\n" .. path, "&Yes\n&No", 2)
    if choice == 1 then
      local ok, err = pcall(vim.fn.delete, path)
      if not ok then
        require("obsidian.log").err("Failed to delete %s: %s", path, err)
        return
      end
      return
    end
  end)
  return
end

---Transform link under cursor: strip wiki/markdown wrapping, autolink external URL,
---prompt to delete attachment files.
local transform_link = function()
  local _, _, range_tuple, ref = api.cursor_link()
  if not ref then
    return
  end

  local start_col, end_col = unpack(range_tuple)
  local row = unpack(vim.api.nvim_win_get_cursor(0))

  if ref.embed == true then
    start_col = start_col - 1
    maybe_delete_attachment(ref.target)
  end

  replace(row, start_col, end_col, ref.target)
end

-- Operatorfunc shim so `.` repeats the transform.
-- See https://vikasraj.dev/blog/vim-dot-repeat
M._opfunc = function()
  transform_link()
end

---Expression mapping: sets operatorfunc and returns `g@l` so the user's keypress
---becomes a single operator invocation that the dot register can replay.
---@return string
M.dl_expr = function()
  vim.go.operatorfunc = "v:lua.require'obsidian.textobj'._opfunc"
  return "g@l"
end

return M
