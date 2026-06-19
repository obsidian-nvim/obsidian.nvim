local M = {}

---Collect tag -> path[] from note rows. Tags are normalized to lowercase.
---@param notes table<string, { tags: string[]? }>
---@return table<string, string[]>
function M.collect(notes)
  local idx = {}
  for path, note in pairs(notes) do
    for _, tag in ipairs(note.tags or {}) do
      local key = tag:lower()
      idx[key] = idx[key] or {}
      idx[key][#idx[key] + 1] = path
    end
  end
  return idx
end

---Return tags matching `query` or nested under `query/`.
---@param idx table<string, string[]>
---@param query string?
---@return string[]
function M.matching(idx, query)
  query = (query or ""):gsub("^#", ""):lower()
  if query == "" then
    local keys = vim.tbl_keys(idx)
    table.sort(keys)
    return keys
  end

  local out = {}
  for tag in pairs(idx) do
    if tag == query or vim.startswith(tag, query .. "/") then
      out[#out + 1] = tag
    end
  end
  table.sort(out)
  return out
end

---Return unique paths for tags.
---@param idx table<string, string[]>
---@param tags string[]
---@param sort_key fun(path: string): string|nil
---@return string[]
function M.paths_for_tags(idx, tags, sort_key)
  local seen = {}
  local out = {}
  for _, tag in ipairs(tags) do
    for _, path in ipairs(idx[tag] or {}) do
      if not seen[path] then
        seen[path] = true
        out[#out + 1] = path
      end
    end
  end
  table.sort(out, function(a, b)
    if sort_key then
      return sort_key(a) < sort_key(b)
    end
    return a < b
  end)
  return out
end

return M
