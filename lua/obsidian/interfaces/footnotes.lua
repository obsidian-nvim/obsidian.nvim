local footnotes = require "obsidian.footnotes"
local log = require "obsidian.log"
local util = require "obsidian.interfaces.util"
local preview = require "obsidian.preview"
local picker_util = require "obsidian.picker.util"

local M = {}

---Select definitions from the captured source buffer.
---@param opts { bufnr: integer?, winid: integer?, workspace_dir: string?, picker: obsidian.PickerSelectOpts? }|?
---@param on_choice fun(definitions: obsidian.footnote.Definition[])
M.pick = function(opts, on_choice)
  opts = opts or {}
  local context = util.capture_context(opts)
  local defs = footnotes.definitions(context.bufnr)
  if vim.tbl_isempty(defs) then
    return log.info "No footnotes in current note"
  end

  local source_path = vim.api.nvim_buf_get_name(context.bufnr)
  local entries = vim.tbl_map(function(def)
    return {
      text = ("[^%s]: %s"):format(def.id, def.text),
      filename = source_path ~= "" and source_path or nil,
      lnum = def.lnum,
      col = 1,
      user_data = def,
    }
  end, defs)
  local function preview_footnote(entry)
    return preview.location {
      bufnr = context.bufnr,
      lnum = entry.lnum,
      filetype = "markdown",
    }
  end

  util.select(
    entries,
    {
      prompt = "Footnotes",
      allow_multiple = true,
      format_item = function(entry)
        return entry.text
      end,
      preview_item = preview_footnote,
      selection_mappings = {
        ["<C-q>"] = picker_util.send_to_qf_mapping { title = "Footnotes" },
      },
    },
    opts.picker,
    function(choices)
      if on_choice then
        on_choice(vim.tbl_map(function(entry)
          return entry.user_data
        end, choices))
      end
    end
  )
end

---Default browsing wrapper; successful selection moves to the definition.
---@param bufnr integer|?
M.open = function(bufnr)
  local context = util.capture_context { bufnr = bufnr }
  return M.pick(context, function(definitions)
    if not util.context_is_valid(context) then
      return
    end
    if #definitions > 1 then
      local entries = vim.tbl_map(function(def)
        return {
          filename = vim.api.nvim_buf_get_name(context.bufnr),
          lnum = def.lnum,
          col = 1,
          text = ("[^%s]: %s"):format(def.id, def.text),
        }
      end, definitions)
      vim.api.nvim_win_call(context.winid, function()
        picker_util.send_to_qf(entries, { title = "Footnotes" })
      end)
      return
    end
    local definition = assert(definitions[1], "footnote selection returned no definition")
    vim.api.nvim_win_set_cursor(context.winid, { definition.lnum, 0 })
  end)
end

return M
