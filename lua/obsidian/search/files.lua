local M = {}

-- Formats that contain Markdown notes and can be parsed by obsidian.Note.
M.markdown_extensions = {
  markdown = true,
  md = true,
  qmd = true,
}

-- Text-based Obsidian formats that are useful in content search, but are not
-- notes and must not be passed to the Markdown parser.
local generic_extensions = {
  base = true,
  canvas = true,
  excalidraw = true,
}

M.extensions = vim.tbl_extend("force", {}, M.markdown_extensions, generic_extensions)

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

return M
