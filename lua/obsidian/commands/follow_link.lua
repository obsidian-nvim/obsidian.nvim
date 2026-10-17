local api = require "obsidian.api"
local picker = require "obsidian.picker"
local picker_util = require "obsidian.picker.util"
local interface_util = require "obsidian.interfaces.util"

--- Deduplicate items by filename (multiple LSP clients may return same file)
---@param items table[]
---@return table[]
local function dedupe_items(items)
  local seen = {}
  local result = {}
  for _, item in ipairs(items) do
    local key = item.filename or item.uri
    if key and not seen[key] then
      seen[key] = true
      result[#result + 1] = item
    end
  end
  return result
end

---@param data obsidian.CommandArgs
return function(data)
  local context = interface_util.capture_context()
  local open_strategy
  if data.args and string.len(data.args) > 0 then
    local strategy = data.args
    ---@cast strategy obsidian.config.OpenStrategy
    open_strategy = api.get_open_strategy(strategy)
  else
    open_strategy = api.get_open_strategy(Obsidian.opts.open_notes_in)
  end

  ---@diagnostic disable-next-line: missing-fields,param-type-mismatch
  vim.lsp.buf.definition {
    on_list = function(t)
      local items = dedupe_items(t.items or {})
      if #items == 0 or not interface_util.context_is_valid(context) then
        return
      elseif #items == 1 then
        vim.api.nvim_win_call(context.winid, function()
          api.open_note(items[1], open_strategy)
        end)
      else
        picker.select(items, {
          prompt = "Resolve link",
          allow_multiple = true,
          selection_mappings = {
            ["<C-q>"] = picker_util.send_to_qf_mapping { title = "Link targets" },
          },
        }, function(choices)
          if not choices or #choices == 0 or not interface_util.context_is_valid(context) then
            return
          end
          vim.api.nvim_win_call(context.winid, function()
            if #choices == 1 then
              api.open_note(choices[1], open_strategy)
            else
              picker_util.send_to_qf(choices, { title = "Link targets" })
            end
          end)
        end)
      end
    end,
  }
end
