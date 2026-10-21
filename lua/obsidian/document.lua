--- Shared parsed snapshots for Neovim buffers.
local Parser = require "obsidian.parse.document"
local values = require("obsidian.cache.volatile").buffer_values { max_entries_per_buffer = 1 }

local M = {}

---@param bufnr integer?
---@return integer
local function normalize_bufnr(bufnr)
  bufnr = bufnr or 0
  if bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

---@param bufnr integer?
M.invalidate = function(bufnr)
  values:invalidate(normalize_bufnr(bufnr))
end

---@param bufnr integer?
---@return obsidian.parse.Document
M.get = function(bufnr)
  bufnr = normalize_bufnr(bufnr)
  assert(vim.api.nvim_buf_is_valid(bufnr), "invalid buffer")
  assert(vim.api.nvim_buf_is_loaded(bufnr), "buffer is not loaded")

  local version = {
    epoch = "document",
    revision = {
      changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
      name = vim.api.nvim_buf_get_name(bufnr),
      line_count = vim.api.nvim_buf_line_count(bufnr),
    },
  }
  local document = values:get(bufnr, "document", version)
  if document then
    return document
  end

  document = Parser.parse(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  values:set(bufnr, "document", version, document)
  return document
end

return M
