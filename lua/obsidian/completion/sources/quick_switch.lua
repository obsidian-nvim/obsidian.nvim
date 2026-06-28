local api = require "obsidian.api"
local search = require "obsidian.search"
local util = require "obsidian.util"
local Path = require "obsidian.path"
local ut = require "obsidian.picker.util"

local M = {}

---@type lsp.CompletionList
local EMPTY_RESPONSE = {
  isIncomplete = true,
  items = {},
}

---@type table<integer, table[]>
local static_candidates_by_buf = {}

---@type table<integer, table>
local source_opts_by_buf = {}

---@type table<integer, table<string, obsidian.PickerEntry>>
local entry_by_label_by_buf = {}

---@type table<integer, integer>
local generation_by_buf = {}

---@param entry obsidian.PickerEntry
---@return string
local function entry_search_text(entry)
  local parts = {}
  for _, key in ipairs { "text", "filename", "user_data" } do
    local value = entry[key]
    if value ~= nil then
      parts[#parts + 1] = tostring(value)
    end
  end
  return table.concat(parts, " ")
end

---@param entry obsidian.PickerEntry
---@return string|?
local function entry_preview_path(entry)
  return entry.filename and tostring(entry.filename) or nil
end

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

---@param values string[]|obsidian.PickerEntry[]
---@param opts obsidian.PickerPickOpts|?
---@return table[]
---@return table<string, obsidian.PickerEntry>
local function build_static_candidates(values, opts)
  opts = opts or {}
  local candidates = {}
  local labels = {}

  for index, value in ipairs(values) do
    ---@type obsidian.PickerEntry
    local entry
    local label

    if type(value) == "string" then
      entry = { user_data = value, text = value }
      label = value
    else
      entry = value
      label = opts.format_item and opts.format_item(value) or ut.make_display(value)
    end

    label = tostring(label or "")
    local preview_path = entry_preview_path(entry)
    local final_label = disambiguate_label(label, preview_path, labels)

    labels[final_label] = entry
    candidates[#candidates + 1] = {
      label = final_label,
      filter_text = final_label .. " " .. entry_search_text(entry),
      sort_text = string.format("%06d", index),
      preview_path = preview_path,
      entry = entry,
    }
  end

  return candidates, labels
end

---@param bufnr integer
---@param values_or_opts string[]|obsidian.PickerEntry[]|table
---@param opts obsidian.PickerPickOpts|?
function M.register(bufnr, values_or_opts, opts)
  M.unregister(bufnr)

  if opts ~= nil or values_or_opts[1] ~= nil then
    local candidates, labels = build_static_candidates(values_or_opts, opts)
    static_candidates_by_buf[bufnr] = candidates
    entry_by_label_by_buf[bufnr] = labels
  else
    source_opts_by_buf[bufnr] = values_or_opts or {}
    entry_by_label_by_buf[bufnr] = {}
  end
end

---@param bufnr integer
function M.unregister(bufnr)
  static_candidates_by_buf[bufnr] = nil
  source_opts_by_buf[bufnr] = nil
  entry_by_label_by_buf[bufnr] = nil
  generation_by_buf[bufnr] = nil
end

---@param bufnr integer
---@param completed table
---@return obsidian.PickerEntry|?
function M.resolve_completed(bufnr, completed)
  local by_label = entry_by_label_by_buf[bufnr]
  if not by_label then
    return nil
  end

  for _, key in ipairs { "word", "abbr" } do
    local label = completed[key]
    if label and by_label[label] then
      return by_label[label]
    end
  end
end

---@param request obsidian.completion.Request
---@return string
local function request_query(request)
  return vim.trim(request.cursor_before_line .. request.cursor_after_line)
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
    }
  end

  return {
    isIncomplete = true,
    items = completion_items,
  }
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

  if note.alt_alias ~= nil then
    aliases[#aliases + 1] = note.alt_alias
  end

  for alias_index, alias in ipairs(aliases) do
    local label = tostring(alias)
    local entry = {
      filename = tostring(note.path),
      text = label,
      user_data = note,
    }
    local preview_path = tostring(note.path)
    local final_label = disambiguate_label(label, preview_path, labels)
    labels[final_label] = entry
    candidates[#candidates + 1] = {
      label = final_label,
      filter_text = table.concat({ label, detail, tostring(note.id) }, " "),
      sort_text = string.format("%06d:%03d", ordinal, alias_index),
      preview_path = preview_path,
      entry = entry,
    }
  end
end

---@param callback fun(resp: lsp.CompletionList)
---@param request obsidian.completion.Request
local function complete_dynamic(callback, request)
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

---@param callback fun(resp: lsp.CompletionList)
---@param request obsidian.completion.Request
function M.process_completion(callback, request)
  if vim.b[request.bufnr].obsidian_completion_source ~= "quick_switch" then
    callback(EMPTY_RESPONSE)
    return
  end

  local static_candidates = static_candidates_by_buf[request.bufnr]
  if static_candidates then
    callback(candidates_to_completion_list(request, static_candidates))
    return
  end

  complete_dynamic(callback, request)
end

return M
