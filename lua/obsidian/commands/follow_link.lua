local api = require "obsidian.api"

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
  local open_strategy
  if data.args and string.len(data.args) > 0 then
    open_strategy = api.get_open_strategy(data.args)
  else
    open_strategy = api.get_open_strategy(Obsidian.opts.open_notes_in)
  end

  vim.lsp.buf.definition {
    on_list = Obsidian.picker and function(t)
      local items = dedupe_items(t.items)
      if #items == 1 then
        api.open_note(items[1], open_strategy)
      else
        Obsidian.picker.pick(items, { prompt_title = "Resolve link" })
      end
    end,
  }
end
