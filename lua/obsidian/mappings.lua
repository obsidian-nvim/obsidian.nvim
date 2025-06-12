local builtin = require "obsidian.builtin"

local M = {}

---@class obsidian.mappings.MappingConfig
---@field action function
---@field opts table

---@return obsidian.mappings.MappingConfig
M.smart_action = function()
  return {
    action = builtin.smart_action,
    opts = { noremap = false, expr = true, buffer = true, desc = "Obsidian smart action" },
  }
end

M.gf_passthrough = function()
  return {
    action = builtin.gf_passthrough,
    opts = { noremap = false, expr = true, buffer = true, desc = "Go to file" },
  }
end

M.toggle_checkbox = function()
  return {
    action = "<cmd>Obsidian toggle_checkbox<cr>",
    opts = { buffer = true, desc = "Toggle Checkbox" },
  }
end

return M
