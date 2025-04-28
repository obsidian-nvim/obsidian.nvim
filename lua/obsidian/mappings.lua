local util = require "obsidian.util"

local M = {}

---@class obsidian.mappings.MappingConfig
---@field action function
---@field opts table

---@return obsidian.mappings.MappingConfig
M.smart_action = function()
  return {
    action = util.smart_action,
    opts = { noremap = false, expr = true, buffer = true, desc = "Obsidian smart action" },
  }
end

---@return obsidian.mappings.MappingConfig
M.gf_passthrough = function()
  return {
    action = util.gf_passthrough,
    opts = { noremap = false, expr = true, buffer = true, desc = "Go to file" },
  }
end

---@return obsidian.mappings.MappingConfig
M.toggle_checkbox = function()
  return {
    action = util.toggle_checkbox,
    opts = { buffer = true, desc = "Toggle Checkbox" },
  }
end

---@return obsidian.mappings.MappingConfig
M.cycle_global = function()
  return {
    action = util.cycle_global,
    opts = { buffer = true, desc = "Cycle file heading state" },
  }
end

---@return obsidian.mappings.MappingConfig
M.cycle = function()
  return {
    action = util.cycle,
    opts = { buffer = true, desc = "Cycle heading state under the cursor" },
  }
end

vim.keymap.set("n", "<Plug>(ObsidianCycle)", util.cycle)
vim.keymap.set("n", "<Plug>(ObsidianCycleGlobal)", util.cycle_global)

return M
