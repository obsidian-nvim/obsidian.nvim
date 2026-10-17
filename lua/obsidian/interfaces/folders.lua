local api = require "obsidian.api"
local util = require "obsidian.interfaces.util"
local log = require "obsidian.log"

local M = {}

---Select a folder under the captured workspace root.
---@param opts { workspace_dir: string?, picker: obsidian.PickerSelectOpts? }|?
---@param on_choice fun(choices: { filename: string, text: string }[])
M.pick = function(opts, on_choice)
  opts = opts or {}
  local context = util.capture_context(opts)
  local root = context.workspace_dir or tostring(api.resolve_workspace_dir())
  if not vim.uv.fs_stat(root) then
    return log.err("Workspace directory does not exist: %s", root)
  end

  local choices = { { filename = root, text = "/" } }
  ---@diagnostic disable-next-line: param-type-mismatch
  for path, kind in vim.fs.dir(root, { depth = math.huge }) do
    if kind == "directory" then
      choices[#choices + 1] = { filename = vim.fs.joinpath(root, path), text = path .. "/" }
    end
  end

  local picker_opts = util.picker_options({
    allow_multiple = false,
    format_item = function(entry)
      return entry.text
    end,
  }, opts.picker)
  picker_opts.allow_multiple = false
  util.select(choices, picker_opts, nil, function(selected)
    on_choice { selected[1] }
  end)
end

---Compatibility browsing wrapper. The legacy callback receives `(directory, text)`.
---@param callback fun(directory: string, text: string)
---@param opts { workspace_dir: string?, picker: obsidian.PickerSelectOpts? }|?
M.open = function(callback, opts)
  M.pick(opts, function(choices)
    local choice = assert(choices[1], "folder selection returned no choice")
    callback(choice.filename, choice.text)
  end)
end

return M
