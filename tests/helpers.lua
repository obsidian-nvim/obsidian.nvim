local Path = require "obsidian.path"
local obsidian = require "obsidian"

local M = {}

---Get a client in a temporary directory.
---
---@param run fun(client: obsidian.Client)
M.with_tmp_client = function(run, dir)
  local tmp
  if not dir then
    tmp = true
    dir = dir or Path.temp { suffix = "-obsidian" }
    dir:mkdir { parents = true }
  end

  local client = obsidian.new_from_dir(tostring(dir))
  client.opts.note_id_func = function(title)
    local id = ""
    if title ~= nil then
      id = title:gsub(" ", "-"):gsub("[^A-Za-z0-9-]", ""):lower()
    else
      for _ = 1, 4 do
        id = id .. string.char(math.random(65, 90))
      end
    end
    return id
  end

  local ok, err = pcall(run, client)

  if tmp then
    vim.fn.delete(tostring(dir), "rf")
  end

  if not ok then
    error(err)
  end
end

return M
