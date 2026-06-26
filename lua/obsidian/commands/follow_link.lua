local api = require "obsidian.api"
local picker = require "obsidian.picker"

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
      if #items == 1 then
        api.open_note(items[1], open_strategy)
      else
        picker.select(items, { prompt = "Resolve link" }, function(choices)
          local entry = choices and choices[1]
          if entry then
            api.open_note(entry)
          end
        end)
      end
    end,
  }
end
