local cache = require "obsidian.cache"

---Resolve a wiki/markdown link target to absolute paths in the cache.
---@param target string  e.g. "bar", "subdir/bar", "subdir/bar.md"
---@param all table<string, table>  cache.notes.all()
---@return string[]  matching abs paths
local function resolve(target, all)
  if target == "" or target:match "^https?://" or target:match "^[a-z]+://" then
    return {}
  end
  local stripped = target:gsub("%.md$", "")
  local hits = {}
  for path, n in pairs(all) do
    if n.basename == stripped or n.rel_path == target or n.rel_path == stripped .. ".md" then
      hits[#hits + 1] = path
    end
  end
  return hits
end

---Build reverse index: target_path → { {source, link} }.
---@return table<string, { source: string, link: table }[]>
local function build_backlinks_for(target_path)
  local all = cache.notes.all()
  local out = {}
  for src_path, n in pairs(all) do
    if src_path ~= target_path then
      for _, link in ipairs(n.links_out or {}) do
        for _, resolved in ipairs(resolve(link.target, all)) do
          if resolved == target_path then
            out[#out + 1] = { source = src_path, link = link }
            break
          end
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.source == b.source then
      return a.link.line < b.link.line
    end
    return a.source < b.source
  end)
  return out
end

local function run()
  if cache.notes.count() == 0 then
    vim.notify("[obsidian] cache empty", vim.log.levels.WARN)
    return
  end

  local cur = vim.api.nvim_buf_get_name(0)
  if cur == "" or not vim.endswith(cur, ".md") then
    vim.notify("[obsidian] not a markdown file", vim.log.levels.WARN)
    return
  end

  local hits = build_backlinks_for(cur)
  if #hits == 0 then
    vim.notify("[obsidian] no backlinks", vim.log.levels.INFO)
    return
  end

  local items = {}
  for _, h in ipairs(hits) do
    local n = cache.notes.find(h.source)
    items[#items + 1] = {
      label = string.format("%s:%d  %s", n and n.rel_path or h.source, h.link.line, h.link.raw),
      path = h.source,
      line = h.link.line,
    }
  end

  vim.ui.select(items, {
    prompt = "Backlinks",
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

return function()
  if not cache.is_enabled() then
    vim.notify("[obsidian] cache disabled", vim.log.levels.WARN)
    return
  end
  cache.when_ready(run)
end
