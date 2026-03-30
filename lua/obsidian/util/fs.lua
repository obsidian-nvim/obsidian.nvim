local function split_path(path)
  local parts = {}
  for part in path:gmatch "[^/]+" do
    table.insert(parts, part)
  end
  return parts
end

local function join_path(parts)
  return table.concat(parts, "/")
end

---@param base string
---@param target string
---@return string|?
local function relpath(base, target)
  base = vim.fs.normalize(vim.fs.abspath(base))
  target = vim.fs.normalize(vim.fs.abspath(target))

  if base == target then
    return "."
  end

  local base_parts = split_path(base)
  local target_parts = split_path(target)

  -- Find common prefix
  local i = 1
  while i <= #base_parts and i <= #target_parts and base_parts[i] == target_parts[i] do
    i = i + 1
  end

  -- Steps up from base to common ancestor
  local ups = {}
  for _ = i, #base_parts do
    table.insert(ups, "..")
  end

  -- Steps down to target from common ancestor
  local downs = {}
  for j = i, #target_parts do
    table.insert(downs, target_parts[j])
  end

  local rel_parts = {}
  vim.list_extend(rel_parts, ups)
  vim.list_extend(rel_parts, downs)

  return #rel_parts > 0 and join_path(rel_parts) or "."
end

return {
  relpath = relpath,
}
