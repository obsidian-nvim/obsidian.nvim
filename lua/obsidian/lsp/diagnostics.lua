local api = require "obsidian.api"
local lsp_util = require "obsidian.lsp.util"
local Path = require "obsidian.path"
local search = require "obsidian.search"
local util = require "obsidian.util"

local M = {}

local SOURCE = "obsidian.links"

local refresh_scheduled = false

---@param path string
---@return boolean
local function path_exists(path)
  return vim.uv.fs_stat(path) ~= nil
end

---@param lines string[]
---@return table<integer, boolean>
local function code_block_line_lookup(lines)
  local lookup = {}
  for _, block in ipairs(search.find_code_blocks(lines)) do
    for lnum = block[1], block[2] do
      lookup[lnum] = true
    end
  end
  return lookup
end

---@param note obsidian.Note
---@param location string
---@param link_type obsidian.search.RefTypes
---@param bufnr integer
---@return boolean
local function link_resolves(note, location, link_type, bufnr)
  location = vim.uri_decode(location)

  if link_type == "HeaderLink" then
    return note:resolve_anchor_link(location) ~= nil
  elseif link_type == "BlockLink" then
    return note:resolve_block(location) ~= nil
  end

  if util.is_uri(location) then
    return true
  end

  if api.is_attachment_path(location) then
    return path_exists(api.resolve_attachment_path(location, bufnr))
  end

  local block_link, anchor_link
  location, block_link = util.strip_block_links(location)
  location, anchor_link = util.strip_anchor_links(location)

  local notes = search.resolve_note(location, {
    notes = { collect_anchor_links = anchor_link ~= nil, collect_blocks = block_link ~= nil },
  })

  if block_link then
    notes = vim.tbl_filter(function(target_note)
      return not vim.tbl_isempty(target_note.blocks or {}) and target_note:resolve_block(block_link) ~= nil
    end, notes)
  end

  if anchor_link then
    notes = vim.tbl_filter(function(target_note)
      return not vim.tbl_isempty(target_note.anchor_links or {}) and target_note:resolve_anchor_link(anchor_link) ~= nil
    end, notes)
  end

  return not vim.tbl_isempty(notes)
end

---@param bufnr integer
---@return lsp.Diagnostic[]
M.collect_unresolved_link_diagnostics = function(bufnr)
  local note = api.current_note(bufnr, { collect_anchor_links = true, collect_blocks = true })
  if not note then
    return {}
  end

  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local old_buf_dir = Obsidian.buf_dir
  local buf_dir = vim.fs.dirname(bufname)
  if buf_dir then
    Obsidian.buf_dir = Path.new(buf_dir)
  end

  local diagnostics = {}
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local code_block_lines = code_block_line_lookup(lines)

  for lnum, line in ipairs(lines) do
    if not code_block_lines[lnum] then
      for _, ref_match in ipairs(search.find_refs(line, { exclude = { "BlockID" } })) do
        local m_start, m_end, match_type = unpack(ref_match)
        local link = line:sub(m_start, m_end)
        local location, _, link_type = util.parse_link(link, { link_type = match_type })

        if location and not link_resolves(note, location, link_type, bufnr) then
          diagnostics[#diagnostics + 1] = lsp_util.make_diagnostic {
            lnum = lnum - 1,
            col = m_start - 1,
            end_col = m_end,
            message = "Unresolved link: " .. location,
            severity = vim.lsp.protocol.DiagnosticSeverity.Warning,
            source = SOURCE,
            code = "unresolved-link",
          }
        end
      end
    end
  end

  Obsidian.buf_dir = old_buf_dir
  return diagnostics
end

---@param bufnr integer
---@return boolean published
M.publish_unresolved_link_diagnostics = function(bufnr)
  return lsp_util.publish_diagnostics(bufnr, M.collect_unresolved_link_diagnostics(bufnr), { source = SOURCE })
end

M.refresh_loaded_buffers = function()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.b[bufnr].obsidian_buffer then
      M.publish_unresolved_link_diagnostics(bufnr)
    end
  end
end

M.schedule_refresh_loaded_buffers = function()
  if refresh_scheduled then
    return
  end

  refresh_scheduled = true
  vim.schedule(function()
    refresh_scheduled = false
    M.refresh_loaded_buffers()
  end)
end

return M
