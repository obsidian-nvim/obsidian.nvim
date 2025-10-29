local M = {}

local log = require "obsidian.log"
local api = require "obsidian.api"
local search = require "obsidian.search"
local ut = require "obsidian.picker.util"

--- Pick from a list of items.
---
---@param values string[]|obsidian.PickerEntry[] Items to pick from.
---@param opts obsidian.PickerPickOpts|? Options.
---
--- Options:
---  `prompt_title`: Title for the prompt window.
---  `callback`: Callback to run with the selected item(s).
---  `allow_multiple`: Allow multiple selections to pass to the callback.
---  `query_mappings`: Mappings that run with the query prompt.
---  `selection_mappings`: Mappings that run with the current selection.
---
M.pick = function(values, opts)
  opts = opts or {}

  if opts.callback then
    vim.ui.select(values, {
      prompt = opts.prompt_title,
      format_item = opts.format_item or function(value)
        return ut.make_display(value)
      end,
    }, function(item)
      if item then
        if type(item) == "string" then
          item = { value = item }
        end
        opts.callback(item)
      end
    end)
  else
    -- HACK: all text
    values = vim.tbl_map(function(value)
      value.text = value.display
      return value
    end, values)
    vim.fn.setqflist(values)
    vim.cmd "copen"
  end
end

--- Grep for a string.
---
---@param opts obsidian.PickerGrepOpts|? Options.
---
--- Options:
---  `prompt_title`: Title for the prompt window.
---  `dir`: Directory to search in.
---  `query`: Initial query to grep for.
---  `callback`: Callback to run with the selected path.
---  `no_default_mappings`: Don't apply picker's default mappings.
---  `query_mappings`: Mappings that run with the query prompt.
---  `selection_mappings`: Mappings that run with the current selection.
---
M.grep = function(opts)
  opts = opts or {}

  ---@param match MatchData
  ---@return vim.quickfix.entry
  local function match_data_to_qfitem(match)
    local filename = match.path.text
    return {
      filename = filename,
      lnum = match.line_number,
      col = match.submatches[1].start + 1,
      text = match.lines.text,
    }
  end

  local query
  if opts.query and vim.trim(opts.query) ~= "" then
    query = opts.query
  else
    query = api.input(opts.prompt_title .. ": ") -- TODO:
  end

  if not query then
    return
  end

  local items = {}

  search.search_async(
    opts.dir,
    query,
    {},
    function(match)
      items[#items + 1] = match_data_to_qfitem(match)
    end,
    vim.schedule_wrap(function(code)
      assert(code == 0, "failed to run ripgrep")

      if vim.tbl_isempty(items) then
        return log.info "Failed to Grep"
      elseif #items == 1 then
        local item = items[1]
        return api.open_buffer(item.filename, {
          line = item.lnum,
          col = item.col,
        })
      else
        vim.fn.setqflist(items)
        vim.cmd "copen"
      end
    end)
  )
end

--- Find files in a directory.
---
---@param opts obsidian.PickerFindOpts|? Options.
---
--- Options:
---  `prompt_title`: Title for the prompt window.
---  `dir`: Directory to search in.
---  `callback`: Callback to run with the selected entry.
---  `no_default_mappings`: Don't apply picker's default mappings.
---  `query_mappings`: Mappings that run with the query prompt.
---  `selection_mappings`: Mappings that run with the current selection.
---
M.find_files = function(opts)
  opts = opts or {}

  local query
  if opts.query and vim.trim(opts.query) ~= "" then
    query = opts.query
  else
    query = api.input(opts.prompt_title .. ": ") -- TODO:
  end

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
            text = ut.make_display {
              filename = path,
            },
          }
        end
        if opts.callback then
          vim.ui.select(items, {
            format_item = function(item)
              return item.text
            end,
          }, function(item)
            if item then
              opts.callback(item.filename)
            end
          end)
        else
          vim.fn.setqflist(items)
          vim.cmd "copen"
        end
      end
    end)
  )
end

return M
