local picker = require "obsidian.picker"
local api = require "obsidian.api"
local log = require "obsidian.log"
local util = require "obsidian.interfaces.util"

local M = {}

---Select exactly one template path.
---@param opts { dir: string?, query: string?, picker: obsidian.PickerSelectOpts? }|?
---@param on_choice fun(paths: string[])
M.pick = function(opts, on_choice)
  opts = opts or {}
  local templates_dir = opts.dir or api.templates_dir()

  if not templates_dir then
    return log.err "Templates folder is not defined or does not exist"
  end
  if not vim.uv.fs_stat(tostring(templates_dir)) then
    return log.err("Templates folder does not exist: %s", tostring(templates_dir))
  end

  local picker_opts = util.picker_options({ no_default_mappings = true }, opts.picker)
  picker.find_files {
    dir = templates_dir,
    query = opts.query,
    prompt_title = picker_opts.prompt,
    no_default_mappings = true,
    query_mappings = picker_opts.query_mappings,
    selection_mappings = picker_opts.selection_mappings,
    allow_multiple = false,
    callback = function(paths)
      if paths and #paths > 0 then
        on_choice { paths[1] }
      end
    end,
  }
end

---Compatibility wrapper for the previous callback-first API.
---@param callback fun(paths: string[])
---@param opts { prompt: string?, dir: string?, query: string?, picker: obsidian.PickerSelectOpts? }|?
M.open = function(callback, opts)
  return M.pick(opts, callback)
end

return M
