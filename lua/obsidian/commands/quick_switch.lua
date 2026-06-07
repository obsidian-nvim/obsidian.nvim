local cache = require "obsidian.cache"

---Build pickable items from cache: one entry per (note × alias) plus the rel_path itself.
---Each item formats as "rel_path" or "rel_path | alias".
---@return table[]
local function build_items()
  local items = {}
  for _, note in pairs(cache.notes.all()) do
    items[#items + 1] = {
      label = note.rel_path,
      path = note.path,
      kind = "path",
    }
    for _, alias in ipairs(note.aliases or {}) do
      items[#items + 1] = {
        label = note.rel_path .. " | " .. alias,
        path = note.path,
        kind = "alias",
      }
    end
  end
  table.sort(items, function(a, b)
    return a.label < b.label
  end)
  return items
end

return function()
  if not cache.is_enabled() then
    vim.notify("[obsidian] cache disabled — enable `cache.enabled = true`", vim.log.levels.WARN)
    return
  end

  cache.when_ready(function()
    if cache.notes.count() == 0 then
      vim.notify("[obsidian] cache empty", vim.log.levels.WARN)
      return
    end
    local items = build_items()
    -- TODO: picker.select
    vim.ui.select(items, {
      prompt = "Quick Switch",
      format_item = function(item)
        return item.label
      end,
      preview_item = function(item)
        local lines = vim.fn.readfile(item.path)
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.bo[buf].filetype = "markdown"
        return { buf = buf }
      end,
    }, function(choice)
      if not choice then
        return
      end
      vim.cmd.edit(vim.fn.fnameescape(choice.path))
    end)
  end)
end
