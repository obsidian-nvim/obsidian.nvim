local log = require "obsidian.log"
local util = require "obsidian.util"
local api = require "obsidian.api"
local search = require "obsidian.search"

---@param tag_locations obsidian.TagLocation[]
---@return string[]
local list_tags = function(tag_locations)
  local tags = {}
  for _, tag_loc in ipairs(tag_locations) do
    local tag = tag_loc.tag
    if not tags[tag] then
      tags[tag] = true
    end
  end
  return vim.tbl_keys(tags)
end

---@param picker obsidian.Picker
---@param tag_locations obsidian.TagLocation[]
---@param tags string[]
local function gather_tag_picker_list(picker, tag_locations, tags)
  ---@type obsidian.PickerEntry[]
  local entries = {}
  for _, tag_loc in ipairs(tag_locations) do
    for _, tag in ipairs(tags) do
      if tag_loc.tag:lower() == tag:lower() or vim.startswith(tag_loc.tag:lower(), tag:lower() .. "/") then
        local display = string.format("%s [%s] %s", tag_loc.note:display_name(), tag_loc.line, tag_loc.text)
        entries[#entries + 1] = {
          value = { path = tag_loc.path, line = tag_loc.line, col = tag_loc.tag_start },
          display = display,
          ordinal = display,
          filename = tostring(tag_loc.path),
          lnum = tag_loc.line,
          col = tag_loc.tag_start,
        }
        break
      end
    end
  end
  if vim.tbl_isempty(entries) then
    if #tags == 1 then
      log.warn "Tag not found"
    else
      log.warn "Tags not found"
    end
    return
  end

  vim.schedule(function()
    picker:pick(entries, {
      prompt_title = "#" .. table.concat(tags, ", #"),
      callback = function(value)
        api.open_buffer(value.filename, { line = value.lnum, col = value.col })
      end,
    })
  end)
end

---@param data obsidian.CommandArgs
return function(data)
  local picker = Obsidian.picker
  if not picker then
    log.err "No picker configured"
    return
  end

  local tags = data.fargs or {}

  if vim.tbl_isempty(tags) then
    local tag = api.cursor_tag()
    if tag then
      tags = { tag }
    end
  end

  if not vim.tbl_isempty(tags) then
    search.find_tags_async(tags, function(tag_locations)
      return gather_tag_picker_list(picker, tag_locations, util.tbl_unique(tags))
    end)
  else
    search.find_tags_async("", function(tag_locations)
      tags = list_tags(tag_locations)
      vim.schedule(function()
        picker:pick(tags, {
          callback = function(...)
            tags = vim.tbl_map(function(v)
              return v.value
            end, { ... })
            gather_tag_picker_list(picker, tag_locations, tags)
          end,
          allow_multiple = true,
        })
      end)
    end)
  end
end
