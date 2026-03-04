local log = require "obsidian.log"

--- Map a URI paneType to a Neovim open command.
---
---@param pane_type string|?
---@return obsidian.config.OpenStrategy|?
local function pane_type_to_open_strategy(pane_type)
  if not pane_type then
    return nil
  end
  local map = {
    -- tab = "tabedit", -- TODO:
    split = "hsplit",
    window = "vsplit", -- no pop-out window in nvim, closest approximation
  }
  local cmd = map[pane_type]
  if not cmd then
    log.warn("Unknown paneType '%s', ignoring", pane_type)
  end
  return cmd
end

return {
  pane_type_to_open_strategy = pane_type_to_open_strategy,
}
