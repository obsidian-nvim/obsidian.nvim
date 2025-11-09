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

---@param tag_locations obsidian.TagLocation[]
---@return table<string, obsidian.TagLocation[]>
local function build_tag_lookup(tag_locations)
  local ret = {}
  for _, tag_loc in ipairs(tag_locations) do
    if not ret[tag_loc.tag] then
      ret[tag_loc.tag] = {}
    end
    table.insert(ret[tag_loc.tag], tag_loc)
  end
  return ret
end

---@param tag_lookup table<string, obsidian.TagLocation[]>
---@param tags string[]
local function pick_tag(tag_lookup, tags)
  local entries = {}
  for _, tag in ipairs(tags) do
    local tag_locs = tag_lookup[tag]
    for _, tag_loc in ipairs(tag_locs) do
      entries[#entries + 1] = {
        text = tag_loc.text,
        filename = tostring(tag_loc.path),
        lnum = tag_loc.line,
        col = tag_loc.tag_start,
      }
    end
  end

  if vim.tbl_isempty(entries) then
    log.warn((#tags == 1 and "Tag" or "Tags") .. " not found")
    return
  end

  vim.schedule(function()
    Obsidian.picker.pick(entries, { prompt = "#" .. table.concat(tags, ", #") }, api.open_note)
  end)
end

---@param data obsidian.CommandArgs
return function(data)
  local tags = data.fargs or {}

  if vim.tbl_isempty(tags) then
    local tag = api.cursor_tag()
    if tag then
      tags = { tag }
    end
  end

  if not vim.tbl_isempty(tags) then
    search.find_tags_async(tags, function(tag_locations)
      return pick_tag(build_tag_lookup(tag_locations), util.tbl_unique(tags))
    end)
  else
    search.find_tags_async("", function(tag_locations)
      tags = list_tags(tag_locations)

      local tag_lookup = build_tag_lookup(tag_locations)

      vim.schedule(function()
        Obsidian.picker.pick(tags, {
          selection_mappings = Obsidian.picker._tag_selection_mappings(),
          allow_multiple = true,
        }, function(...)
          local tgs = vim.tbl_map(function(v)
            return v.user_data
          end, { ... })
          pick_tag(tag_lookup, tgs)
        end)
      end)
    end)
  end
end
