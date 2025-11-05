local api = require "obsidian.api"

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
      if #t.items == 1 then
        api.open_note(t.items[1], open_strategy)
      else
        Obsidian.picker.pick(t.items, { prompt_title = "Resolve link" })
      end
    end,
  }
end
