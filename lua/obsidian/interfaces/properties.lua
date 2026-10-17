local api = require "obsidian.api"
local log = require "obsidian.log"
local util = require "obsidian.interfaces.util"
local property = require "obsidian.property"
local picker_util = require "obsidian.picker.util"

local M = {}

---@param entry obsidian.PropertyCount
---@return string
local function format_count(entry)
  return string.format("%s (%d)", entry.name, entry.count)
end

---@param records obsidian.PropertyRecord[]
---@param key string
---@param value string
---@param opts { bufnr: integer?, winid: integer?, workspace_dir: string?, picker: obsidian.PickerSelectOpts? }
---@param on_choice fun(records: obsidian.PropertyRecord[])|?
local function pick_notes(records, key, value, opts, on_choice)
  local matches = {}
  for _, record in ipairs(records) do
    if property.has_value(record, key, value) then
      matches[#matches + 1] = {
        text = record.display_name,
        filename = record.path,
        user_data = record,
      }
    end
  end
  if #matches == 0 then
    return log.warn "No notes found with that property value"
  end

  util.select(
    matches,
    {
      prompt = string.format("%s: %s", key, value),
      allow_multiple = true,
      selection_mappings = {
        ["<C-q>"] = picker_util.send_to_qf_mapping { title = string.format("%s: %s", key, value) },
      },
      format_item = function(entry)
        return entry.text
      end,
    },
    opts.picker,
    function(choices)
      if on_choice then
        on_choice(vim.tbl_map(function(entry)
          return entry.user_data
        end, choices))
      end
    end
  )
end

---@param opts { key: string?, value: string?, dir: string?, bufnr: integer?, winid: integer?, workspace_dir: string?, picker: obsidian.PickerSelectOpts? }|?
---@param on_choice fun(records: obsidian.PropertyRecord[])|?
M.pick = function(opts, on_choice)
  opts = opts or {}
  local context = util.capture_context(opts)
  property.list_async({ dir = opts.dir or context.workspace_dir }, function(keys, records)
    if opts.key and opts.value then
      pick_notes(records, opts.key, opts.value, opts, on_choice)
      return
    end

    if opts.key then
      local values = property.values(records, opts.key)
      if #values == 0 then
        return log.warn "No values found for that property"
      end
      util.select(values, { prompt = opts.key, format_item = format_count }, opts.picker, function(choices)
        pick_notes(records, opts.key, choices[1].name, opts, on_choice)
      end)
      return
    end

    if #keys == 0 then
      return log.warn "No properties found"
    end
    util.select(keys, { prompt = "Properties", format_item = format_count }, opts.picker, function(choices)
      local key = choices[1].name
      local values = property.values(records, key)
      if #values == 0 then
        return log.warn "No values found for that property"
      end
      util.select(values, { prompt = key, format_item = format_count }, opts.picker, function(value_choices)
        pick_notes(records, key, value_choices[1].name, opts, on_choice)
      end)
    end)
  end)
end

---Default browsing wrapper. A custom selection callback replaces note opening.
---@param key string|?
---@param value string|?
---@param opts { picker: obsidian.PickerSelectOpts?, bufnr: integer?, winid: integer?, workspace_dir: string? }|?
M.open = function(key, value, opts)
  opts = opts or {}
  local context = util.capture_context(opts)
  local pick_opts = vim.tbl_extend("force", {}, opts, { key = key, value = value })
  return M.pick(pick_opts, function(records)
    if not util.context_is_valid(context) then
      return
    end
    vim.api.nvim_win_call(context.winid, function()
      if #records == 1 then
        api.open_note { filename = records[1].path }
      else
        local entries = vim.tbl_map(function(record)
          return { filename = record.path, text = record.display_name }
        end, records)
        picker_util.send_to_qf(entries, { title = "Property notes" })
      end
    end)
  end)
end

return M
