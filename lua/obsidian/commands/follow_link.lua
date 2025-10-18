local api = require "obsidian.api"
local log = require "obsidian.log"

---@param data obsidian.CommandArgs
return function(data)
  local opts = {}
  if data.args and string.len(data.args) > 0 then
    opts.open_strategy = data.args
  end

  vim.lsp.buf.definition {
    on_list = Obsidian.picker and function(t)
      if #t.items == 1 then
        vim.print(t.items[1])
        -- TODO: proper lnum
        -- TODO: open_strategy here!
        vim.cmd("e " .. t.items[1].filename)
      else
        Obsidian.picker:pick(t.items, {
          prompt_title = "Resolve link",
          callback = function(v)
            -- TODO: open strat here?
            api.open_buffer(v.filename, { col = v.col, line = v.lnum })
          end,
        })
      end
    end,
  }
end
