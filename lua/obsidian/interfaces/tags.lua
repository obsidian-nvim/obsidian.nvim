local log = require "obsidian.log"
local api = require "obsidian.api"
local tag_module = require "obsidian.tag"
local picker = require "obsidian.picker"
local picker_util = require "obsidian.picker.util"
local search = require "obsidian.search"
local util = require "obsidian.interfaces.util"

local M = {}

---Browse matching tag occurrences. Entries retain their source occurrence in `user_data`.
---@param tag_locations obsidian.TagLocation[]
---@param tags string[]
---@param opts { bufnr: integer?, winid: integer?, workspace_dir: string?, picker: obsidian.PickerSelectOpts? }|?
---@param on_choice fun(entries: obsidian.PickerEntry[])|?
M.browse = function(tag_locations, tags, opts, on_choice)
  opts = opts or {}
  local context = util.capture_context(opts)
  local entries = {}
  for _, tag_loc in ipairs(tag_locations) do
    for _, tag in ipairs(tags) do
      if tag_module.matches(tag_loc.tag, tag, "subtree") then
        local display = string.format("%s [%s] %s", tag_loc.note:display_name(), tag_loc.line, tag_loc.text)
        entries[#entries + 1] = {
          text = display,
          filename = tostring(tag_loc.path),
          lnum = tag_loc.line,
          col = tag_loc.tag_start,
          user_data = tag_loc,
        }
        break
      end
    end
  end
  if #entries == 0 then
    return log.warn(#tags == 1 and "Tag not found" or "Tags not found")
  end

  util.select(
    entries,
    {
      prompt = "#" .. table.concat(tags, ", #"),
      allow_multiple = true,
      format_item = function(entry)
        return entry.text
      end,
      selection_mappings = {
        ["<C-q>"] = picker_util.send_to_qf_mapping { title = "Tag occurrences" },
      },
    },
    opts.picker,
    function(choices)
      if on_choice then
        on_choice(choices)
      elseif util.context_is_valid(context) then
        picker_util.open_notes(choices, { title = "Tag occurrences" })
      end
    end
  )
end

---Select tag identities without taking an action on the selected values.
---@param opts { dir: string?, picker: obsidian.PickerSelectOpts? }|?
---@param on_choice fun(tags: string[])
M.pick = function(opts, on_choice)
  opts = opts or {}
  tag_module.list(function(tags)
    if #tags == 0 then
      return log.warn "No tags found"
    end
    util.select(
      tags,
      {
        allow_multiple = true,
        selection_mappings = picker._tag_selection_mappings(),
      },
      opts.picker,
      function(choices)
        on_choice(choices)
      end
    )
  end, { dir = opts.dir })
end

---Compatibility browsing wrapper.
---@param callback fun(tags: string[])
---@param title string|?
M.open = function(callback, title)
  return M.pick({ picker = { prompt = title } }, callback)
end

---Run the tag search workflow for explicit identities.
---@param tags string[]
---@param opts { dir: string?, bufnr: integer?, winid: integer?, workspace_dir: string?, picker: obsidian.PickerSelectOpts? }|?
M.search = function(tags, opts)
  opts = opts or {}
  search.find_tags_async(tags, function(tag_locations)
    M.browse(tag_locations, tags, opts)
  end, { dir = opts.dir or api.resolve_workspace_dir(), match = "subtree" })
end

return M
