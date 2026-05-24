local obsidian = require "obsidian"

return function()
  require "obsidian.lsp.handlers._references"(nil, { tag = false }, function(_, locations)
    local items = vim.lsp.util.locations_to_items(locations, "utf-8")
    if #items == 0 then
      obsidian.log.info "No backlinks"
      return
    end
    if #items == 1 then
      obsidian.api.open_note(items[1])
    else
      Obsidian.picker.pick(items, {
        prompt_title = "Resolve link",
        format_item = function(item)
          return vim.fs.basename(item.filename) .. ":" .. item.lnum .. " - " .. vim.trim(item.text)
        end,
        callback = function(selected_item)
          if selected_item then
            obsidian.api.open_note(selected_item)
          end
        end,
      })
    end
  end)
end
