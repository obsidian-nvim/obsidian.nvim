local M = {}

local Ui = require "obsidian.picker.ui"

--- Pick from a list of items.
---
M.select = Ui.select

--- Grep for a string.
---@param opts obsidian.PickerGrepOpts | nil
---@return obsidian.picker.ui.Picker
M.grep = function(opts)
  ---@diagnostic disable-next-line: param-type-mismatch
  return Ui.live_grep(opts)
end

return M
