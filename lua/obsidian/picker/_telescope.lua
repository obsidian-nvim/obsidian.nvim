local telescope = require "telescope.builtin"
local telescope_actions = require "telescope.actions"
local actions_state = require "telescope.actions.state"

local obsidian = require "obsidian"
local search = obsidian.search
local Path = obsidian.Path
local log = obsidian.log
local Picker = obsidian.Picker
local ut = require "obsidian.picker.util"

local M = {}

---@param prompt_bufnr integer
---@param keep_open boolean|?
---@return table|?
local function get_entry(prompt_bufnr, keep_open)
  local entry = actions_state.get_selected_entry()
  if entry and not keep_open then
    telescope_actions.close(prompt_bufnr)
  end

  if entry.index ~= nil then -- is find/grep entry
    return {
      filename = entry.path,
      lnum = entry.lnum,
      col = entry.col,
      user_data = entry.value,
    }
  end

  if entry.filename then -- is pick entry
    return entry
  end
end

---@param prompt_bufnr integer
---@param keep_open boolean|?
---@param allow_multiple boolean|?
---@return obsidian.PickerEntry[]?
local function get_selected(prompt_bufnr, keep_open, allow_multiple)
  ---
  ---@return obsidian.PickerEntry
  local function selection_to_entry(selection)
    return selection.raw
  end

  local picker = actions_state.get_current_picker(prompt_bufnr)
  local entries = picker:get_multi_selection()
  if entries and #entries > 0 then
    if #entries > 1 and not allow_multiple then
      log.err "This mapping does not allow multiple entries"
      return
    end

    if not keep_open then
      telescope_actions.close(prompt_bufnr)
    end

    return vim.tbl_map(selection_to_entry, entries)
  else
    local entry = get_entry(prompt_bufnr, keep_open)

    if entry then
      return { entry }
    end
  end
end

---@param prompt_bufnr integer
---@param keep_open boolean|?
---@param initial_query string|?
---@return string|?
local function get_query(prompt_bufnr, keep_open, initial_query)
  local query = actions_state.get_current_line()
  if not query or string.len(query) == 0 then
    query = initial_query
  end
  if query and string.len(query) > 0 then
    if not keep_open then
      telescope_actions.close(prompt_bufnr)
    end
    return query
  else
    return nil
  end
end

---@param opts { callback: fun(entry: obsidian.PickerEntry)|?, allow_multiple: boolean|?, query_mappings: obsidian.PickerMappingTable|?, selection_mappings: obsidian.PickerMappingTable|?, initial_query: string|? }
local function attach_picker_mappings(map, opts)
  -- Docs for telescope actions:
  -- https://github.com/nvim-telescope/telescope.nvim/blob/master/lua/telescope/actions/init.lua

  if opts.query_mappings then
    for key, mapping in pairs(opts.query_mappings) do
      map({ "i", "n" }, key, function(prompt_bufnr)
        local query = get_query(prompt_bufnr, false, opts.initial_query)
        if query then
          mapping.callback(query)
        end
      end)
    end
  end

  if opts.selection_mappings then
    for key, mapping in pairs(opts.selection_mappings) do
      map({ "i", "n" }, key, function(prompt_bufnr)
        local entries = get_selected(prompt_bufnr, mapping.keep_open, mapping.allow_multiple)
        if entries then
          mapping.callback(unpack(entries))
        elseif mapping.fallback_to_query then
          local query = get_query(prompt_bufnr, mapping.keep_open)
          if query then
            mapping.callback(query)
          end
        end
      end)
    end
  end

  if opts.callback then
    map({ "i", "n" }, "<CR>", function(prompt_bufnr)
      local entries = get_selected(prompt_bufnr, false, opts.allow_multiple)
      if not entries then
        return
      end
      if vim.tbl_isempty(entries) then
        return
      end
      if type(entries[1].user_data) == "function" then
        entries[1].user_data()
      elseif opts.callback then
        opts.callback(unpack(entries))
        return
      end
    end)
  end
end

---@param opts obsidian.PickerFindOpts|? Options.
M.find_files = function(opts)
  opts = opts or {}
  opts.callback = opts.callback or obsidian.api.open_note

  local prompt_title = ut.build_prompt {
    prompt_title = opts.prompt_title,
    query_mappings = opts.query_mappings,
    selection_mappings = opts.selection_mappings,
  }

  telescope.find_files {
    default_text = opts.query,
    prompt_title = prompt_title,
    cwd = opts.dir and tostring(opts.dir) or tostring(Obsidian.dir),
    find_command = search.build_find_cmd(),
    attach_mappings = function(_, map)
      attach_picker_mappings(map, {
        callback = function(entry)
          opts.callback(entry.filename)
        end,
        query_mappings = opts.query_mappings,
        selection_mappings = opts.selection_mappings,
      })
      return true
    end,
  }
end

---@param opts obsidian.PickerGrepOpts|? Options.
M.grep = function(opts)
  opts = opts or {}

  local cwd = opts.dir and Path.new(opts.dir) or Obsidian.dir

  local prompt_title = ut.build_prompt {
    prompt_title = opts.prompt_title,
    query_mappings = opts.query_mappings,
    selection_mappings = opts.selection_mappings,
  }

  local attach_mappings = function(_, map)
    attach_picker_mappings(map, {
      callback = opts.callback,
      query_mappings = opts.query_mappings,
      selection_mappings = opts.selection_mappings,
      initial_query = opts.query,
    })
    return true
  end

  if opts.query and string.len(opts.query) > 0 then
    telescope.grep_string {
      prompt_title = prompt_title,
      cwd = tostring(cwd),
      vimgrep_arguments = search.build_grep_cmd(),
      search = opts.query,
      attach_mappings = attach_mappings,
    }
  else
    telescope.live_grep {
      prompt_title = prompt_title,
      cwd = tostring(cwd),
      vimgrep_arguments = search.build_grep_cmd(),
      attach_mappings = attach_mappings,
    }
  end
end

---@param values string[]|obsidian.PickerEntry[]
---@param opts obsidian.PickerPickOpts|? Options.
M.pick = function(values, opts)
  local pickers = require "telescope.pickers"
  local finders = require "telescope.finders"
  local conf = require "telescope.config"
  local make_entry = require "telescope.make_entry"

  Picker.state.calling_bufnr = vim.api.nvim_get_current_buf()

  opts = opts and opts or {}
  opts.callback = opts.callback or obsidian.api.open_note

  local picker_opts = {
    attach_mappings = function(_, map)
      attach_picker_mappings(map, {
        callback = opts.callback,
        allow_multiple = opts.allow_multiple,
        query_mappings = opts.query_mappings,
        selection_mappings = opts.selection_mappings,
      })
      return true
    end,
  }

  local displayer = function(entry)
    return opts.format_item and opts.format_item(entry.raw) or ut.make_display(entry.raw)
  end

  local prompt_title = ut.build_prompt {
    prompt_title = opts.prompt_title,
    query_mappings = opts.query_mappings,
    selection_mappings = opts.selection_mappings,
  }

  local previewer
  if type(values[1]) == "table" then
    previewer = conf.values.grep_previewer(picker_opts)
    -- Get theme to use.
    if conf.pickers then
      for _, picker_name in ipairs { "grep_string", "live_grep", "find_files" } do
        local picker_conf = conf.pickers[picker_name]
        if picker_conf and picker_conf.theme then
          picker_opts =
            vim.tbl_extend("force", picker_opts, require("telescope.themes")["get_" .. picker_conf.theme] {})
          break
        end
      end
    end
  end

  local make_entry_from_string = make_entry.gen_from_string(picker_opts)

  pickers
    .new(picker_opts, {
      prompt_title = prompt_title,
      finder = finders.new_table {
        results = values,
        entry_maker = function(v)
          if type(v) == "string" then
            return make_entry_from_string(v)
          else
            return {
              value = v.text,
              display = displayer,
              ordinal = v.filename, -- NOTE: not sure
              filename = v.filename,
              lnum = v.lnum,
              col = v.col,
              raw = v,
            }
          end
        end,
      },
      sorter = conf.values.generic_sorter(picker_opts),
      previewer = previewer,
    })
    :find()
end

return M
