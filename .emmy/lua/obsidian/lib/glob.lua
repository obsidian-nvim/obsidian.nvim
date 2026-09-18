---@meta

---@class Glob
local Glob = {}

---@param path string
---@return boolean
function Glob:check(path) end

---@param paths string[]
---@return "accepted"|"refused"|"unknown"
function Glob:status(paths) end

---@class Glob.Options
---@field ignoreCase? boolean
---@field asGitIgnore? boolean
---@field root? string

---@class Glob.Interface
---@field type? fun(path: string):('file'|'directory'|nil)
---@field list? fun(path: string):string[]?
---@field patterns? fun(path: string):string[]?

local M = {}

---@param pattern? string|string[]
---@param options? Glob.Options
---@param interface? Glob.Interface
---@return Glob
function M.gitignore(pattern, options, interface) end

return M
