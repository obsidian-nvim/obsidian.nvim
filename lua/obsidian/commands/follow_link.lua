local api = require "obsidian.api"

---@param data obsidian.CommandArgs
return function(data)
  local open_strategy
  if data.args and string.len(data.args) > 0 then
    open_strategy = api.get_open_strategy(data.args)
  else
    open_strategy = api.get_open_strategy(Obsidian.opts.open_notes_in)
  end

  local on_list

  if not Obsidian.picker.state._native then
    on_list = function(t)
      if #t.items == 1 then
        api.open_note(t.items[1], open_strategy)
      else
        Obsidian.picker.pick(t.items, { prompt = "Resolve link" }) -- calls open_qf_entry by default
      end
    end
  end

  vim.lsp.buf.definition { on_list = on_list }
end
