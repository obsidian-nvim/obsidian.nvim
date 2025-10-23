local Picker = require "obsidian.pickers.picker"
local abc = require "obsidian.abc"
local api = require "obsidian.api"
local search = require "obsidian.search"
local log = require "obsidian.log"

---@class obsidian.pickers.DefaultPicker : obsidian.Picker
local DefaultPicker = abc.new_class({
  __tostring = function()
    return "MiniPicker()"
  end,
}, Picker)

--- Use input + qf for find_files TODO: no callback
---@param opts obsidian.PickerFindOpts|? Options.
DefaultPicker.find_files = function(self, opts)
  opts = opts or {}

  local query = api.input "Quick Switch: "

  if not query then
    return
  end

  local paths = {}

  search.find_async(
    opts.dir,
    query,
    {},
    function(path)
      paths[#paths + 1] = path
    end,
    vim.schedule_wrap(function()
      if vim.tbl_isempty(paths) then
        return log.info "Failed to Switch" -- TODO:
      elseif #paths == 1 then
        return api.open_buffer(paths[1])
      elseif #paths > 1 then
        ---@type vim.quickfix.entry
        local items = {}
        for _, path in ipairs(paths) do
          items[#items + 1] = {
            filename = path,
            lnum = 1,
            col = 0,
            text = self:_make_display {
              filename = path,
            },
          }
        end
        vim.fn.setqflist(items)
        vim.cmd "copen"
      end
    end)
  )
end

return DefaultPicker
