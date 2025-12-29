local parser = require "obsidian.yaml.lua.parser"

local M = {}

---Deserialize a YAML string.
---@param str string
---@return any
---@return string[]
M.loads = function(str)
  return parser.loads(str)
end

M.name = "lua"

return M
