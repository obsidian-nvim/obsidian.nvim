local api = require "obsidian.api"
local picker = require "obsidian.picker"
local picker_util = require "obsidian.picker.util"
local interface_util = require "obsidian.interfaces.util"

return function()
  local context = interface_util.capture_context()
  require "obsidian.lsp.handlers._references"(nil, { tag = false }, function(_, locations)
    local items = vim.lsp.util.locations_to_items(locations, "utf-8")
    if #items == 0 then
      return
    elseif #items == 1 then
      if interface_util.context_is_valid(context) then
        vim.api.nvim_win_call(context.winid, function()
          api.open_note(items[1])
        end)
      end
    else
      picker.select(items, {
        prompt = "Backlinks",
        allow_multiple = true,
        selection_mappings = {
          ["<C-q>"] = picker_util.send_to_qf_mapping { title = "Backlinks" },
        },
      }, function(choices)
        if not choices or #choices == 0 or not interface_util.context_is_valid(context) then
          return
        end
        vim.api.nvim_win_call(context.winid, function()
          picker_util.open_notes(choices, { title = "Backlinks" })
        end)
      end)
    end
  end)
end
