local log = require "obsidian.log"
local util = require "obsidian.util"
local api = require "obsidian.api"
local Tags = require "obsidian.tags"
local Note = require "obsidian.note"

---@param picker obsidian.Picker
---@param tags string[]
local function gather_tag_picker_list(picker, tags)
  local entries = {}

  Tags.find(tags, {
    on_match = function(tag_loc)
      for _, tag in ipairs(tags) do
        if tag_loc.tag == tag or vim.startswith(tag_loc.tag, tag .. "/") then
          local note = Note.from_file(tag_loc.path)
          local display = string.format("%s [%s] %s", note:display_name(), tag_loc.line, tag_loc.tag)
          entries[#entries + 1] = {
            value = { path = tag_loc.path, line = tag_loc.line, col = tag_loc.tag_start },
            display = display,
            ordinal = display,
            filename = tag_loc.path,
            lnum = tag_loc.line,
            col = tag_loc.tag_start,
          }
          break
        end
      end
    end,
  }, function()
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
  end)
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
    return gather_tag_picker_list(picker, util.tbl_unique(tags))
  else
    Tags.list(function(all_tags)
      vim.schedule(function()
        -- Open picker with tags.
        picker:pick_tag(all_tags, {
          callback = function(...)
            gather_tag_picker_list(picker, { ... })
          end,
          allow_multiple = true,
        })
      end)
    end)
  end
end
