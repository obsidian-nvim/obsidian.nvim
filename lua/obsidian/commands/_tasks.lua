local cache = require "obsidian.cache"

local function run(data)
  if cache.notes.count() == 0 then
    vim.notify("[obsidian] cache empty", vim.log.levels.WARN)
    return
  end

  local arg = (data and data.args or ""):gsub("^%s+", ""):gsub("%s+$", "")
  ---@type fun(t: table): boolean
  local filter
  if arg == "" or arg == "all" then
    filter = function()
      return true
    end
  elseif arg == "done" then
    filter = function(t)
      return t.done
    end
  elseif arg == "open" or arg == "todo" then
    filter = function(t)
      return not t.done
    end
  else
    local want = arg:sub(1, 1)
    filter = function(t)
      return t.state == want
    end
  end

  local items = {}
  local paths = vim.tbl_keys(cache.notes.all())
  table.sort(paths, function(a, b)
    local na = cache.notes.find(a)
    local nb = cache.notes.find(b)
    return (na and na.rel_path or a) < (nb and nb.rel_path or b)
  end)

  for _, path in ipairs(paths) do
    local n = cache.notes.find(path)
    if n and n.tasks then
      for _, t in ipairs(n.tasks) do
        if filter(t) then
          items[#items + 1] = {
            label = string.format("%s:%d  [%s] %s", n.rel_path, t.line, t.state, t.text),
            path = path,
            line = t.line,
          }
        end
      end
    end
  end

  if #items == 0 then
    vim.notify("[obsidian] no tasks" .. (arg ~= "" and " (" .. arg .. ")" or ""), vim.log.levels.INFO)
    return
  end

  vim.ui.select(items, {
    prompt = "Tasks" .. (arg ~= "" and " (" .. arg .. ")" or ""),
    format_item = function(it)
      return it.label
    end,
  }, function(choice)
    if not choice then
      return
    end
    vim.cmd.edit(vim.fn.fnameescape(choice.path))
    pcall(vim.api.nvim_win_set_cursor, 0, { choice.line, 0 })
  end)
end

---@param data obsidian.CommandArgs
return function(data)
  if not cache.is_enabled() then
    vim.notify("[obsidian] cache disabled", vim.log.levels.WARN)
    return
  end
  cache.when_ready(function()
    run(data)
  end)
end
