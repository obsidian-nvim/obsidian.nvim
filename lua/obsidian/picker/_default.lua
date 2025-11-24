local M = {}

local obsidian = require "obsidian"
local log = obsidian.log
local api = obsidian.api
local search = obsidian.search
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
  opts.callback = opts.callback or obsidian.api.open_note

  if opts.callback then
    vim.ui.select(values, {
      prompt = opts.prompt_title,
      format_item = opts.format_item or function(value)
        if type(value) == "string" then
          return value
        elseif type(value) == "table" then
          return ut.make_display(value)
        end
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
        return api.open_note(items[1])
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

  _G.ob_api = require "obsidian.api"

  local query
  if opts.query and vim.trim(opts.query) ~= "" then
    query = opts.query
  else
    vim.cmd [[
    function! ObsidianPathComplete(A, L, P)
      return v:lua.ob_api.path_completion(a:A,a:L,a:P)
    endfunction
       ]]
    query = api.input(opts.prompt_title .. ": ", {
      completion = "customlist,ObsidianPathComplete",
    })
  end

  if not query then
    return
  end
  api.quick_switch(query, opts)
end

return M
