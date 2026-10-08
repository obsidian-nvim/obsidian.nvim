local BufferDocument = require "obsidian.document"
local Document = require "obsidian.parse.document"
local Path = require "obsidian.path"
local api = require "obsidian.api"
local async = require "obsidian.async"
local log = require "obsidian.log"
local parse_highlight = require "obsidian.parse.highlight"
local search = require "obsidian.search"
local SearchOpts = require "obsidian.search.opts"

local M = {}

---@class obsidian.HighlightLocation : obsidian.parse.Highlight
---@field path obsidian.Path?
---@field filename string?
---@field lnum integer 1-indexed line number.
---@field col integer 1-indexed byte column.
---@field end_lnum integer 1-indexed end line number.
---@field end_col integer 1-indexed exclusive byte column.

---@class obsidian.highlights.FindOpts
---@field document obsidian.parse.Document?
---@field path string|obsidian.Path?

---Find highlights in a document snapshot.
---@param lines string[]
---@param opts obsidian.highlights.FindOpts?
---@return obsidian.HighlightLocation[]
M.find = function(lines, opts)
  opts = opts or {}
  local document = opts.document or Document.parse(lines)
  local path = opts.path and Path.new(opts.path):resolve() or nil
  local filename = path and tostring(path) or nil
  local matches = {}

  for lnum, line in ipairs(lines) do
    for _, match in ipairs(parse_highlight.extract(line, { row = lnum - 1 })) do
      if not document:intersects(match.range, Document.BODY_EXCLUSIONS) then
        matches[#matches + 1] = vim.tbl_extend("force", match, {
          path = path,
          filename = filename,
          lnum = match.range.start_row + 1,
          col = match.range.start_col + 1,
          end_lnum = match.range.end_row + 1,
          end_col = match.range.end_col + 1,
        })
      end
    end
  end

  return matches
end

---Find highlights in a loaded note.
---@param note obsidian.Note
---@return obsidian.HighlightLocation[]
M.find_note = function(note)
  local lines = note.raw_contents or note.contents or {}
  return M.find(lines, { path = note.path })
end

---Find highlights in a buffer, including unsaved changes.
---@param bufnr integer?
---@return obsidian.HighlightLocation[]
M.find_buffer = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local document = BufferDocument.get(bufnr)
  local filename = vim.api.nvim_buf_get_name(bufnr)
  return M.find(document.lines, {
    document = document,
    path = filename ~= "" and filename or nil,
  })
end

---@class obsidian.highlights.VaultOpts
---@field dir string|obsidian.Path?
---@field search obsidian.SearchOpts?
---@field timeout integer? Timeout in milliseconds for synchronous searches.

---Find all highlights in the vault asynchronously.
---Ripgrep only selects candidate files; the source parser and Document decide
---which delimiter pairs are actual, non-excluded highlights.
---@param callback fun(matches: obsidian.HighlightLocation[])
---@param opts obsidian.highlights.VaultOpts?
---@return vim.SystemObj handle
M.find_vault_async = function(callback, opts)
  opts = opts or {}
  local dir = opts.dir or api.resolve_workspace_dir()
  local processed = {}
  local paths = {}

  ---@param match_data MatchData
  local function on_match(match_data)
    local path = match_data.path.text
    if not processed[path] then
      processed[path] = true
      paths[#paths + 1] = path
    end
  end

  return search.search_async(
    dir,
    "==",
    SearchOpts._prepare(opts.search, { fixed_strings = true, max_count_per_file = 1 }),
    on_match,
    function(code)
      -- vim.system stdout/exit callbacks run in a fast event context. Schedule
      -- file reads, logging, and the consumer callback on the main loop.
      vim.schedule(function()
        if code ~= 0 and code ~= 1 then
          callback {}
          return
        end

        local matches = {}
        local errors = 0
        local first_error
        local first_error_path
        for _, candidate in ipairs(paths) do
          local path = Path.new(candidate):resolve()
          local ok, lines = pcall(vim.fn.readfile, tostring(path))
          if not ok then
            errors = errors + 1
            first_error = first_error or lines
            first_error_path = first_error_path or path
          else
            for i, line in ipairs(lines) do
              lines[i] = line:gsub("\r$", "")
            end
            vim.list_extend(matches, M.find(lines, { path = path }))
          end
        end

        table.sort(matches, function(a, b)
          local a_path, b_path = tostring(a.path), tostring(b.path)
          if a_path ~= b_path then
            return a_path < b_path
          elseif a.range.start_row ~= b.range.start_row then
            return a.range.start_row < b.range.start_row
          else
            return a.range.start_col < b.range.start_col
          end
        end)

        if first_error then
          log.err(
            "%d error(s) occurred during highlight search. First error from '%s':\n%s",
            errors,
            first_error_path,
            first_error
          )
        end
        callback(matches)
      end)
    end
  )
end

---Synchronous wrapper around `find_vault_async()`.
---@param opts obsidian.highlights.VaultOpts|?
---@return obsidian.HighlightLocation[] matches
M.find_vault = function(opts)
  opts = opts or {}
  local timeout = opts.timeout or 1000
  local result = async.block_on(function(done)
    M.find_vault_async(done, opts)
  end, timeout)
  ---@cast result obsidian.HighlightLocation[]?
  return result or {}
end

return M
