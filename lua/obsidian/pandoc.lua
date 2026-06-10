local async = require "obsidian.async"

local M = {}

---Whether the `pandoc` executable is available.
---@return boolean
M.available = function()
  return vim.fn.executable "pandoc" == 1
end

---Convert a string of HTML to GitHub-flavored markdown by piping it through pandoc.
---
---@param html string
---@param callback fun(markdown: string?, err: string?)
---@return any job
M.convert_async = function(html, callback)
  if not M.available() then
    callback(nil, "pandoc is not executable")
    return
  end

  local cmd = { "pandoc", "-f", "html", "-t", "gfm-raw_html", "--wrap=none" }

  local lines = {}
  return async.run_job_async(cmd, function(line)
    table.insert(lines, line)
  end, function(code)
    local out = table.concat(lines, "\n")
    if code ~= 0 then
      callback(nil, ("pandoc failed (%d)"):format(code))
      return
    end
    callback(out, nil)
  end, { stdin = html })
end

return M
