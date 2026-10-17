local api = require "obsidian.api"
local log = require "obsidian.log"
local picker_util = require "obsidian.picker.util"
local util = require "obsidian.interfaces.util"
local heading_data = require "obsidian.heading"

local M = {}

---Select headings from the captured buffer snapshot.
---@param opts { bufnr: integer?, winid: integer?, workspace_dir: string?, picker: obsidian.PickerSelectOpts? }|?
---@param on_choice fun(headings: obsidian.HeadingLocation[])
M.pick = function(opts, on_choice)
  opts = opts or {}
  local context = util.capture_context(opts)
  local headings = heading_data.list(context.bufnr)
  if #headings == 0 then
    return log.warn "no headings found"
  end

  local entries = vim.tbl_map(function(location)
    return {
      filename = location.path,
      text = string.rep("#", location.level) .. " " .. location.header,
      lnum = location.line,
      col = location.section.heading_range.start_col + 1,
      range = location.section.range,
      user_data = location,
    }
  end, headings)

  util.select(
    entries,
    {
      prompt = "Table of Contents",
      allow_multiple = true,
      selection_mappings = {
        ["<C-q>"] = picker_util.send_to_qf_mapping { title = "Table of Contents" },
      },
    },
    opts.picker,
    function(choices)
      on_choice(vim.tbl_map(function(entry)
        return entry.user_data
      end, choices))
    end
  )
end

---Default browsing wrapper; opens one heading or exports multiple locations.
---@param callback fun(headings: obsidian.HeadingLocation[])|?
---@param opts { bufnr: integer?, winid: integer?, workspace_dir: string?, picker: obsidian.PickerSelectOpts? }|?
M.open = function(callback, opts)
  opts = opts or {}
  local context = util.capture_context(opts)
  return M.pick(opts, function(headings)
    if callback then
      callback(headings)
    elseif util.context_is_valid(context) then
      vim.api.nvim_win_call(context.winid, function()
        if #headings == 1 then
          local heading = headings[1]
          api.open_note {
            filename = heading.path,
            lnum = heading.line,
            col = heading.section.heading_range.start_col + 1,
            range = heading.section.range,
          }
        else
          local entries = vim.tbl_map(function(heading)
            return {
              filename = heading.path,
              lnum = heading.line,
              col = heading.section.heading_range.start_col + 1,
              range = heading.section.range,
              text = string.rep("#", heading.level) .. " " .. heading.header,
              user_data = heading,
            }
          end, headings)
          picker_util.send_to_qf(entries, { title = "Table of Contents" })
        end
      end)
    end
  end)
end

return M
