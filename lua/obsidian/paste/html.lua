local Clipboard = require "obsidian.clipboard"
local M = {}

-- TODO: pure treesitter conversion
function M.convert(raw)
  return vim.system({ "pandoc", "-f", "html", "-t", "markdown" }, { stdin = raw }):wait().stdout
end

---@return string[] markdown_string
function M.get()
  local src = vim.fn.system(Clipboard.get_get_command "text/html")
  return vim.split(M.convert(src), "\n")
end

function M.has()
  local result_string = vim.fn.system(Clipboard.get_check_command())
  local content = vim.split(result_string, "\n")
  return vim.list_contains(content, "text/html")
end

return M
