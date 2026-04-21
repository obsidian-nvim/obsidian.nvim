--- Format dispatch. Each backend under `obsidian.stats.formats.<name>` exports
--- a single `render(stats, opts) -> string`. Add new formats by dropping a
--- file in and -- optionally -- registering it here. Lazy-loaded.

local M = {}

---@type table<string, string>
M.backends = {
  markdown = "obsidian.stats.formats.markdown",
  json = "obsidian.stats.formats.json",
  csv = "obsidian.stats.formats.csv",
}

---@param stats obsidian.stats.VaultStats
---@param format string
---@param opts table|?
---@return string
function M.render(stats, format, opts)
  local modname = M.backends[format]
  if not modname then
    error(string.format("unknown stats format '%s'", format))
  end
  return require(modname).render(stats, opts or {})
end

return M
