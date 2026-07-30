local api = require "obsidian.api"
local picker = require "obsidian.picker"
local util = require "obsidian.util"

return function()
  require "obsidian.lsp.handlers._references"(nil, { tag = false }, function(_, locations)
    local items = vim.lsp.util.locations_to_items(locations, "utf-8")
    if #items == 1 then
      api.open_note(items[1])
    else
      picker.select(items, {
        prompt = "Resolve link",
        preview_item = function(entry)
          ---@cast entry obsidian.PickerEntry
          local filename = entry.filename
          ---@cast filename -nil
          local preview = util.preview_path(filename)
          preview.pos = { entry.lnum or 1, entry.col and math.max(entry.col - 1, 0) or 0 }
          return preview
        end,
      }, function(choices)
        local entry = choices and choices[1]
        if entry then
          api.open_note(entry)
        end
      end)
    end
  end)
end
