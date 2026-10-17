local api = require "obsidian.api"
local picker = require "obsidian.picker"

local M = {}

---@param defaults obsidian.PickerSelectOpts
---@param overrides obsidian.PickerSelectOpts|?
---@return obsidian.PickerSelectOpts
M.picker_options = function(defaults, overrides)
  overrides = overrides or {}
  local result = vim.tbl_extend("force", {}, defaults, overrides)

  for _, key in ipairs { "query_mappings", "selection_mappings" } do
    local mappings = {}
    if not overrides.no_default_mappings then
      mappings = vim.tbl_extend("force", mappings, defaults[key] or {})
    end
    for lhs, mapping in pairs(overrides[key] or {}) do
      if mapping == false then
        mappings[lhs] = nil
      else
        mappings[lhs] = mapping
      end
    end
    local configured = (not overrides.no_default_mappings and defaults[key] ~= nil) or overrides[key] ~= nil
    result[key] = configured and mappings or nil
  end

  return result
end

---Run a primitive picker and expose only successful, nonempty selections.
---@param values any[]
---@param defaults obsidian.PickerSelectOpts
---@param overrides obsidian.PickerSelectOpts|?
---@param on_choice fun(choices: any[])
M.select = function(values, defaults, overrides, on_choice)
  if not values or #values == 0 then
    return
  end

  picker.select(values, M.picker_options(defaults, overrides), function(choices)
    if type(choices) == "table" and #choices > 0 then
      on_choice(choices)
    end
  end)
end

---Capture the source buffer/window and workspace before a picker can yield.
---@param opts { bufnr: integer?, winid: integer?, workspace_dir: string? }|?
---@return { bufnr: integer, winid: integer, workspace_dir: string? }
M.capture_context = function(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  local workspace_dir = opts.workspace_dir or api.resolve_workspace_dir(path ~= "" and path or nil)
  return {
    bufnr = bufnr,
    winid = opts.winid or vim.api.nvim_get_current_win(),
    workspace_dir = workspace_dir and tostring(workspace_dir) or nil,
  }
end

---@param context { bufnr: integer, winid: integer }
---@return boolean
M.context_is_valid = function(context)
  return vim.api.nvim_buf_is_valid(context.bufnr) and vim.api.nvim_win_is_valid(context.winid)
end

return M
