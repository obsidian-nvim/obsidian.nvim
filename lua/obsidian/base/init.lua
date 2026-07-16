local parser = require "obsidian.base.parser"

local M = {
  expression = require "obsidian.base.expression",
  property = require "obsidian.base.property",
  parse = parser.parse,
}

---@param filter obsidian.base.Filter?
---@param visitor fun(node: obsidian.base.Filter)
function M.walk_filter(filter, visitor)
  if filter == nil then
    return
  end
  visitor(filter)
  if filter.kind == "filter_group" then
    for _, child in ipairs(filter.children) do
      M.walk_filter(child, visitor)
    end
  end
end

---Return the global and view filters composed exactly as Bases evaluates them.
---@param document obsidian.base.Document
---@param view obsidian.base.View
---@return obsidian.base.Filter?
function M.effective_filter(document, view)
  if document.filters == nil then
    return view.filters
  elseif view.filters == nil then
    return document.filters
  end
  return {
    kind = "filter_group",
    operator = "and",
    children = { document.filters, view.filters },
    synthetic = true,
  }
end

---@param document obsidian.base.Document
---@param name? string
---@return obsidian.base.View?
function M.select_view(document, name)
  if name == nil or name == "" then
    return document.views[1]
  end
  for _, view in ipairs(document.views) do
    if view.name == name then
      return view
    end
  end
  return nil
end

return M
