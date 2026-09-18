--- Shared parsed snapshots for Neovim buffers.
local Parser = require "obsidian.parse.document"

local M = {}

---@class obsidian.document.CacheEntry
---@field changedtick integer
---@field document obsidian.parse.Document
---@field name string
---@field line_count integer

---@type table<integer, obsidian.document.CacheEntry>
local cache = {}
---@type table<integer, boolean>
local attached = {}

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
  bufnr = normalize_bufnr(bufnr)
  cache[bufnr] = nil
end

---@param bufnr integer?
---@return obsidian.parse.Document
M.get = function(bufnr)
  bufnr = normalize_bufnr(bufnr)
  assert(vim.api.nvim_buf_is_valid(bufnr), "invalid buffer")
  assert(vim.api.nvim_buf_is_loaded(bufnr), "buffer is not loaded")

  local changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local entry = cache[bufnr]
  if entry and entry.changedtick == changedtick and entry.name == name and entry.line_count == line_count then
    return entry.document
  end

  local document = Parser.parse(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  cache[bufnr] = {
    changedtick = changedtick,
    document = document,
    name = name,
    line_count = line_count,
  }

  if not attached[bufnr] then
    attached[bufnr] = vim.api.nvim_buf_attach(bufnr, false, {
      on_reload = function(_, reloaded_bufnr)
        cache[reloaded_bufnr] = nil
      end,
      on_detach = function(_, detached_bufnr)
        cache[detached_bufnr] = nil
        attached[detached_bufnr] = nil
      end,
    })
  end

  return document
end

return M
