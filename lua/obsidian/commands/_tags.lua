local cache = require "obsidian.cache"

---Collect tag → path[] from cache. Tags lowercased.
---@return table<string, string[]>
local function collect()
  local idx = {}
  for _, note in pairs(cache.notes.all()) do
    for _, t in ipairs(note.tags or {}) do
      idx[t] = idx[t] or {}
      idx[t][#idx[t] + 1] = note.path
    end
  end
  return idx
end

---@param idx table<string, string[]>
---@param query string  may be empty; matches `q` or `q/...` (nested)
---@return string[]
local function tags_matching(idx, query)
  if query == "" then
    local keys = vim.tbl_keys(idx)
    table.sort(keys)
    return keys
  end
  local q = query:lower()
  local out = {}
  for tag in pairs(idx) do
    if tag == q or vim.startswith(tag, q .. "/") then
      out[#out + 1] = tag
    end
  end
  table.sort(out)
  return out
end

---@param idx table<string, string[]>
---@param tags string[]
---@return string[] paths  unique, sorted by rel_path
local function paths_for_tags(idx, tags)
  local seen = {}
  local out = {}
  for _, t in ipairs(tags) do
    for _, p in ipairs(idx[t] or {}) do
      if not seen[p] then
        seen[p] = true
        out[#out + 1] = p
      end
    end
  end
  table.sort(out, function(a, b)
    local na = cache.notes.find(a)
    local nb = cache.notes.find(b)
    return (na and na.rel_path or a) < (nb and nb.rel_path or b)
  end)
  return out
end

---@param paths string[]
local function pick_note(paths, tag_label)
  if #paths == 0 then
    vim.notify("[obsidian] no notes for tag #" .. tag_label, vim.log.levels.INFO)
    return
  end
  local items = {}
  for _, p in ipairs(paths) do
    local n = cache.notes.find(p)
    items[#items + 1] = {
      label = n and n.rel_path or p,
      path = p,
    }
  end
  vim.ui.select(items, {
    prompt = "Notes #" .. tag_label,
    format_item = function(it)
      return it.label
    end,
  }, function(choice)
    if not choice then
      return
    end
    vim.cmd.edit(vim.fn.fnameescape(choice.path))
  end)
end

local function run(data)
  if cache.notes.count() == 0 then
    vim.notify("[obsidian] cache empty", vim.log.levels.WARN)
    return
  end

  local idx = collect()
  local query = (data and data.args or ""):gsub("^#", ""):gsub("^%s+", ""):gsub("%s+$", "")
  local matched = tags_matching(idx, query)

  if #matched == 0 then
    vim.notify("[obsidian] no tags" .. (query ~= "" and " matching '" .. query .. "'" or ""), vim.log.levels.INFO)
    return
  end

  if query ~= "" then
    pick_note(paths_for_tags(idx, matched), query)
    return
  end

  local items = {}
  for _, t in ipairs(matched) do
    items[#items + 1] = { tag = t, count = #idx[t] }
  end
  vim.ui.select(items, {
    prompt = "Tags",
    format_item = function(it)
      return string.format("#%s (%d)", it.tag, it.count)
    end,
  }, function(choice)
    if not choice then
      return
    end
    pick_note(paths_for_tags(idx, tags_matching(idx, choice.tag)), choice.tag)
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
