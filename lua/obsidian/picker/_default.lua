local M = {}

local log = require "obsidian.log"
local api = require "obsidian.api"
local search = require "obsidian.search"
local ut = require "obsidian.picker.util"

--- Pick from a list of items.
---
---@param values string[]|obsidian.PickerEntry[] Items to pick from.
---@param opts obsidian.PickerSelectOpts|? Options.
---@param on_choice fun(choices: any[])|?
---
--- Options:
---  `prompt`: Title for the prompt window.
---  `format_item`: Function to format an item for display.
---  `preview_item`: Function to preview an item.
---  `allow_multiple`: Allow multiple selections to pass to the callback.
---
M.select = function(values, opts, on_choice)
  opts = opts or {}
  on_choice = on_choice or function() end

  vim.ui.select(values, {
    prompt = opts.prompt,
    kind = opts.kind,
    allow_multiple = opts.allow_multiple,
    preview_item = opts.preview_item,
    format_item = opts.format_item or function(value)
      if type(value) == "string" then
        return value
      elseif type(value) == "table" then
        return ut.make_display(value)
      end
    end,
  }, function(choice_or_choices, idx)
    if choice_or_choices == nil then
      on_choice {}
    elseif idx == nil and type(choice_or_choices) == "table" then
      on_choice(choice_or_choices)
    else
      on_choice { choice_or_choices }
    end
  end)
end

---@param match MatchData
---@return vim.quickfix.entry
local function match_data_to_qfitem(match)
  local filename = match.path.text
  return {
    filename = filename,
    lnum = match.line_number,
    col = match.submatches[1] and match.submatches[1].start + 1,
    text = match.lines.text,
  }
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

  local query
  if opts.query and vim.trim(opts.query) ~= "" then
    query = opts.query
  else
    query = api.input(opts.prompt_title or "Grep")
  end

  if not query then
    return
  end

  local dir = opts.dir or api.resolve_workspace_dir()

  local items = {}

  search.search_async(
    dir,
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

  local query
  if opts.query and vim.trim(opts.query) ~= "" then
    query = opts.query
  else
    query = api.input(opts.prompt_title or "Find files")
  end

  if not query then
    return
  end

  local paths = {}

  local dir = opts.dir or api.resolve_workspace_dir()

  search.find_async(
    dir,
    query,
    { include_non_markdown = opts.include_non_markdown },
    function(path)
      paths[#paths + 1] = path
    end,
    vim.schedule_wrap(function()
      if vim.tbl_isempty(paths) then
        return log.info "Search result empty"
      elseif #paths == 1 then
        if opts.callback then
          return opts.callback(paths[1])
        else
          return api.open_note { filename = paths[1] }
        end
      elseif #paths > 1 then
        ---@type vim.quickfix.entry[]
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
            if item and item.filename then
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
