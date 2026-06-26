local api = require "obsidian.api"
local picker = require "obsidian.picker"

return function()
  require "obsidian.lsp.handlers._references"(nil, { tag = false }, function(_, locations)
    local items = vim.lsp.util.locations_to_items(locations, "utf-8")
    if #items == 1 then
      api.open_note(items[1])
    else
      picker.select(items, { prompt = "Resolve link" }, function(choices)
        local entry = choices and choices[1]
        if entry then
          api.open_note(entry)
        end
      end)
    end
  end)
end
