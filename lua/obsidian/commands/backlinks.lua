local obsidian = require "obsidian"

return function()
  require "obsidian.lsp.handlers._references"(nil, { tag = false }, function(_, locations)
    local items = vim.lsp.util.locations_to_items(locations, "utf-8")
    if #items == 1 then
      obsidian.api.open_note(items[1])
    else
      Obsidian.picker.pick(items, { prompt_title = "Resolve link" }) -- calls open_qf_entry by default
    end
  end)
end
