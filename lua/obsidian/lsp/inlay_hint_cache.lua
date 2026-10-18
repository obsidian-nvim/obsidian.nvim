local volatile = require "obsidian.cache.volatile"

local M = {}
local values = volatile.buffer_values { max_entries_per_buffer = 16 }

---@param uri string?
---@param range lsp.Range|?
---@return string
local function response_key(uri, range)
  return (uri or "buffer") .. ":" .. vim.inspect(range)
end

---@return string
local function epoch()
  local root = Obsidian and Obsidian.dir and tostring(Obsidian.dir) or ""
  return root .. ":" .. tostring(require("obsidian.cache").generation())
end

---@param bufnr integer
---@return table
local function revision(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return { valid = false }
  end
  return {
    changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
    name = vim.api.nvim_buf_get_name(bufnr),
  }
end

---@param uri string?
---@param bufnr integer
---@param range lsp.Range|?
---@param opts { allow_stale: boolean? }|?
---@return lsp.InlayHint[]?
function M.get(uri, bufnr, range, opts)
  return values:get(bufnr, response_key(uri, range), {
    epoch = epoch(),
    revision = revision(bufnr),
  }, opts)
end

---@param uri string?
---@param bufnr integer
---@param range lsp.Range|?
---@param hints lsp.InlayHint[]
function M.set(uri, bufnr, range, hints)
  values:set(bufnr, response_key(uri, range), {
    epoch = epoch(),
    revision = revision(bufnr),
  }, vim.deepcopy(hints))
end

---@param bufnr integer|?
function M.invalidate(bufnr)
  values:invalidate(bufnr)
end

return M
