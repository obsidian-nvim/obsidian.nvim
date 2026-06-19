local M = {}

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
function M.relpath(base, target)
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

---@param path string
---@param root string
---@return boolean
function M.is_subpath(path, root)
  path = vim.fs.normalize(path):gsub("/+$", "")
  root = vim.fs.normalize(root):gsub("/+$", "")
  return path == root or vim.startswith(path, root .. "/")
end

---@param path string
---@param contents string
function M.atomic_write(path, contents)
  local tmp = path .. ".tmp"
  local f, err = io.open(tmp, "w")
  if not f then
    error("cannot open " .. tmp .. ": " .. tostring(err))
  end
  f:write(contents)
  f:close()
  local ok, rename_err = os.rename(tmp, path)
  if not ok then
    error("rename failed: " .. tostring(rename_err))
  end
end

return M
