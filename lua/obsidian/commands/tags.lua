local log = require "obsidian.log"
local util = require "obsidian.util"
local api = require "obsidian.api"

---@param client obsidian.Client
---@param picker obsidian.Picker
---@param tags string[]
local function gather_tag_picker_list(client, picker, tags)
  client:find_tags_async(tags, function(tag_locations)
    -- Format results into picker entries, filtering out results that aren't exact matches or sub-tags.
    ---@type obsidian.PickerEntry[]
    local entries = {}
    for _, tag_loc in ipairs(tag_locations) do
      for _, tag in ipairs(tags) do
        if tag_loc.tag == tag or vim.startswith(tag_loc.tag, tag .. "/") then
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
          api.open_buffer(value.path, { line = value.line, col = value.col })
        end,
      })
    end)
  end, { search = { sort = true } })
end

---@param client obsidian.Client
---@param data CommandArgs
return function(client, data)
  local picker = client:picker()
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
    return gather_tag_picker_list(client, picker, util.tbl_unique(tags))
  else
    client:list_tags_async(nil, function(all_tags)
      vim.schedule(function()
        -- Open picker with tags.
        picker:pick_tag(all_tags, {
          callback = function(...)
            gather_tag_picker_list(client, picker, { ... })
          end,
          allow_multiple = true,
        })
      end)
    end)
  end
end
