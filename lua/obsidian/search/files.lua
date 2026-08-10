local M = {}

M.extensions = {
  base = true,
  canvas = true,
  markdown = true,
  md = true,
  qmd = true,
}

M.markdown_extensions = {
  base = true,
  markdown = true,
  md = true,
  qmd = true,
}

---@param path string
---@return string
function M.extension(path)
  return (path:match "%.([^./]+)$" or ""):lower()
end

---@param path string
---@return boolean
function M.is_searchable(path)
  return M.extensions[M.extension(path)] == true
end

---@param path string
---@return boolean
function M.is_markdown(path)
  return M.markdown_extensions[M.extension(path)] == true
end

---@return string[]
function M.ripgrep_globs()
  local globs = {}
  for extension in pairs(M.extensions) do
    globs[#globs + 1] = "*." .. extension
  end
  table.sort(globs)
  return globs
end

return M
