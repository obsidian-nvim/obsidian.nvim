local M = {}

---@class obsidian.parse.Task
---@field indent integer
---@field state string
---@field text string

---Match `- [x] foo`, `* [ ] foo`, `+ [ ] foo`, `1. [ ] foo`, or `1) [ ] foo`.
---@param line string
---@return obsidian.parse.Task?
function M.match_task(line)
  local indent, state, text = line:match "^(%s*)[-%*%+] %[(.)%] (.*)$"
  if state then
    return { indent = #indent, state = state, text = text }
  end

  indent, state, text = line:match "^(%s*)%d+[%.%)] %[(.)%] (.*)$"
  if state then
    return { indent = #indent, state = state, text = text }
  end
end

return M
