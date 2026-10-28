---@meta

---@class obsidian.lib.Glob
local Glob = {}

---@param path string
---@return boolean
function Glob:check(path) end

---@param paths string[]
---@return "accepted"|"refused"|"unknown"
function Glob:status(paths) end

---@class obsidian.lib.GlobOptions
---@field ignoreCase? boolean
---@field asGitIgnore? boolean
---@field root? string

---@class obsidian.lib.GlobInterface
---@field type? fun(path: string):('file'|'directory'|nil)
---@field list? fun(path: string):string[]?
---@field patterns? fun(path: string):string[]?

local M = {}

---@param pattern? string|string[]
---@param options? obsidian.lib.GlobOptions
---@param interface? obsidian.lib.GlobInterface
---@return obsidian.lib.Glob
function M.gitignore(pattern, options, interface) end

return M
