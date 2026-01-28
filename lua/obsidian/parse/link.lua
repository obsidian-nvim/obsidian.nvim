local M = {}

local ts = vim.treesitter

local query_str = [[ (inline_link)@link ]]

--- Find refs and URLs.
---@param src string the string to search
---@param opts? { exclude: obsidian.search.RefTypes[] }
---
---@return { [1]: integer, [2]: integer, [3]: obsidian.search.RefTypes }[]
M.find_refs = function(src)
  local parser = ts.get_string_parser(src, "markdown_inline", {})
  local trees = parser:parse()
  if not trees then
    vim.notify "failed to parse line for refs"
    return {}
  end
  local root_node = trees[1]:root()
  local query = ts.query.parse("markdown_inline", query_str)
  local result = {}

  for _, node in query:iter_captures(root_node, src) do
    local _, st_col = node:start()
    local _, ed_col = node:end_()
    result[#result + 1] = {
      st_col + 1,
      ed_col + 1,
      "Markdown",
      ts.get_node_text(node, src),
    }
  end

  return result
end

-- local search = require "obsidian.search"
--
-- -- vim.print(search.find_refs "- [name](loc.md)")
-- -- vim.print(M.find_refs "- [name](loc.md)")
--
-- vim.print(search.find_refs "- [[wiki note]]")
-- vim.print(M.find_refs "- [[wiki note]]")
--
return M
