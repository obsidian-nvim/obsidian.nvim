local api = require "obsidian.api"
local search = require "obsidian.search"
local util = require "obsidian.util"
local Path = require "obsidian.path"

local M = {}

M.SELECT_COMMAND = "obsidian.quick_switch_select"

---@type lsp.CompletionList
local EMPTY_RESPONSE = {
  isIncomplete = true,
  items = {},
}

---@type table<integer, table>
local source_opts_by_buf = {}

---@type table<integer, table<string, obsidian.PickerEntry>>
local entry_by_label_by_buf = {}

---@type table<integer, integer>
local generation_by_buf = {}

---@param label string
---@param preview_path string|?
---@param labels table<string, obsidian.PickerEntry>
---@return string
local function disambiguate_label(label, preview_path, labels)
  if labels[label] and preview_path then
    local ok, rel = pcall(function()
      return Path.new(preview_path):vault_relative_path()
    end)
    return string.format("%s — %s", label, ok and rel or preview_path)
  end
  return label
end

---@param bufnr integer
---@param opts table|?
function M.register(bufnr, opts)
  M.unregister(bufnr)
  source_opts_by_buf[bufnr] = opts or {}
  entry_by_label_by_buf[bufnr] = {}
end

---@param bufnr integer
function M.unregister(bufnr)
  source_opts_by_buf[bufnr] = nil
  entry_by_label_by_buf[bufnr] = nil
  generation_by_buf[bufnr] = nil
end

---@param bufnr integer
---@param label string
---@return obsidian.PickerEntry|?
function M.resolve_label(bufnr, label)
  local by_label = entry_by_label_by_buf[bufnr]
  return by_label and by_label[label] or nil
end

---@param bufnr integer
---@param completed table
---@return obsidian.PickerEntry|?
function M.resolve_completed(bufnr, completed)
  for _, key in ipairs { "word", "abbr" } do
    local label = completed[key]
    if label then
      local entry = M.resolve_label(bufnr, label)
      if entry then
        return entry
      end
    end
  end
end

---@param request obsidian.completion.Request
---@return string
local function request_query(request)
  return vim.trim(request.cursor_before_line .. request.cursor_after_line)
end

---@param note obsidian.Note
---@return string
local function note_detail(note)
  local ok, rel = pcall(function()
    return Path.new(note.path):vault_relative_path()
  end)
  if ok then
    return tostring(rel)
  end
  return tostring(note.path)
end

---@param note obsidian.Note
---@param labels table<string, obsidian.PickerEntry>
---@param candidates table[]
---@param ordinal integer
local function add_note_candidates(note, labels, candidates, ordinal)
  local detail = note_detail(note)
  local aliases = util.tbl_unique { tostring(note.id), note:display_name(), unpack(note.aliases or {}) }

  for alias_index, alias in ipairs(aliases) do
    local label = tostring(alias)
    local preview_path = tostring(note.path)
    local final_label = disambiguate_label(label, preview_path, labels)
    local entry = {
      filename = preview_path,
      text = label,
      user_data = note,
    }

    labels[final_label] = entry
    candidates[#candidates + 1] = {
      label = final_label,
      filter_text = table.concat({ label, detail, tostring(note.id) }, " "),
      sort_text = string.format("%06d:%03d", ordinal, alias_index),
      preview_path = preview_path,
    }
  end
end

---@param request obsidian.completion.Request
---@param candidates table[]
---@return lsp.CompletionList
local function candidates_to_completion_list(request, candidates)
  local line_text = request.cursor_before_line .. request.cursor_after_line
  local completion_items = {}

  for _, candidate in ipairs(candidates) do
    completion_items[#completion_items + 1] = {
      label = candidate.label,
      sortText = candidate.sort_text,
      filterText = candidate.filter_text,
      kind = vim.lsp.protocol.CompletionItemKind.File,
      data = candidate.preview_path and {
        obsidian_preview_path = candidate.preview_path,
      } or nil,
      textEdit = {
        newText = candidate.label,
        range = {
          ["start"] = {
            line = request.line,
            character = 0,
          },
          ["end"] = {
            line = request.line,
            character = #line_text,
          },
        },
      },
      command = {
        command = M.SELECT_COMMAND,
        title = "Open note",
        arguments = { request.bufnr, candidate.label },
      },
    }
  end

  return {
    isIncomplete = true,
    items = completion_items,
  }
end

---@param callback fun(resp: lsp.CompletionList)
---@param request obsidian.completion.Request
function M.process_completion(callback, request)
  if vim.b[request.bufnr].obsidian_completion_source ~= "quick_switch" then
    callback(EMPTY_RESPONSE)
    return
  end

  local source_opts = source_opts_by_buf[request.bufnr]
  if not source_opts then
    callback(EMPTY_RESPONSE)
    return
  end

  local query = request_query(request)
  if #query < Obsidian.opts.completion.min_chars then
    callback(EMPTY_RESPONSE)
    return
  end

  local gen = (generation_by_buf[request.bufnr] or 0) + 1
  generation_by_buf[request.bufnr] = gen

  search.find_notes_async(query, function(results)
    if generation_by_buf[request.bufnr] ~= gen then
      callback(EMPTY_RESPONSE)
      return
    end

    local labels = {}
    local candidates = {}
    for index, note in ipairs(results) do
      add_note_candidates(note, labels, candidates, index)
    end

    entry_by_label_by_buf[request.bufnr] = labels
    callback(candidates_to_completion_list(request, candidates))
  end, {
    dir = source_opts.dir or api.resolve_workspace_dir(),
    search = {
      sort = false,
      include_templates = false,
      ignore_case = true,
    },
  })
end

return M
