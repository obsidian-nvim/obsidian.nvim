local log = require "obsidian.log"

return function()
  local workspace = Obsidian.workspace
  if not workspace or workspace.name == ".obsidian.wiki" then
    return log.err "Select a vault workspace before exporting app settings"
  end
  local ok, result = pcall(require("obsidian.config.export").write, workspace)
  if not ok then
    return log.err("Could not export Obsidian app settings: %s", result)
  end
  log.info("Exported app settings to '%s'", vim.fs.dirname(result[1]))
  local reloaded, err = pcall(require("obsidian.workspace").set, workspace)
  if not reloaded then
    log.err("App settings were exported, but could not be reloaded: %s", err)
  end
end
