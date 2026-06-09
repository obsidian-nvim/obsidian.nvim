local async = require "obsidian.async"

local M = {}

---@class obsidian.http.Response
---@field body string
---@field code integer

---@class obsidian.http.FetchOpts
---@field timeout integer? timeout in seconds
---@field headers string[]?
---@field args string[]? extra curl args

---@param url string
---@param opts obsidian.http.FetchOpts|?
---@param callback fun(body:string?, err:string?, code:integer?)
---@return any job
M.fetch_async = function(url, opts, callback)
  opts = opts or {}

  local cmd = { "curl", "-fsL", "--compressed", "-m", tostring(opts.timeout or 15) }

  for _, header in ipairs(opts.headers or {}) do
    table.insert(cmd, "-H")
    table.insert(cmd, header)
  end

  for _, arg in ipairs(opts.args or {}) do
    table.insert(cmd, arg)
  end

  table.insert(cmd, url)

  local lines = {}
  return async.run_job_async(cmd, function(line)
    table.insert(lines, line)
  end, function(code)
    local body = table.concat(lines, "\n")
    if code ~= 0 or body == "" then
      callback(nil, ("curl failed (%d)"):format(code), code)
      return
    end
    callback(body, nil, code)
  end)
end

return M
