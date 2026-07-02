---@diagnostic disable: unresolved-require
local api = require "obsidian.api"
local search = require "obsidian.search"
local Path = require "obsidian.path"
local log = require "obsidian.log"
local Picker = require "obsidian.picker"
local ut = require "obsidian.picker.util"

---@param prompt_title string|?
---@return string|?
local function format_prompt(prompt_title)
  if not prompt_title then
    return
  else
    return prompt_title .. " ❯ "
  end
end

---@param keymap string
---@return string
local function format_keymap(keymap)
  keymap = string.lower(keymap)
  keymap = string.gsub(keymap, vim.pesc "<c-", "ctrl-")
  keymap = string.gsub(keymap, vim.pesc ">", "")
  return keymap
end

local M = {}

---@param opts { callback: (fun(selection: obsidian.PickerEntry|string))|?, no_default_mappings: boolean|?, selection_mappings: obsidian.PickerMappingTable|?, query_mappings: obsidian.PickerMappingTable|? }
---@param path_only? boolean HACK:
local function get_selection_actions(opts, path_only)
  local entry_to_file = require("fzf-lua.path").entry_to_file

  local actions = {
    default = function(selected, fzf_opts)
      if opts.callback then
        local path = entry_to_file(selected[1], fzf_opts).path
        if path_only then
          opts.callback(path)
        else
          opts.callback { filename = path }
        end
      elseif not opts.no_default_mappings then
        require("fzf-lua.actions").file_edit_or_qf(selected, fzf_opts)
      end
    end,
  }

  if opts.selection_mappings then
    for key, mapping in pairs(opts.selection_mappings) do
      actions[format_keymap(key)] = function(selected, fzf_opts)
        local path = entry_to_file(selected[1], fzf_opts).path
        mapping.callback { filename = path }
      end
    end
  end

  if opts.query_mappings then
    for key, mapping in pairs(opts.query_mappings) do
      actions[format_keymap(key)] = function(_, fzf_opts)
        local query = fzf_opts.query
        mapping.callback(query)
      end
    end
  end

  return actions
end

---@param display_to_value_map table<string, any>
---@param opts { on_choice: fun(choices: any[])|?, allow_multiple: boolean|?, selection_mappings: obsidian.PickerMappingTable|? }
local function get_value_actions(display_to_value_map, opts)
  ---@param allow_multiple boolean|?
  ---@return any[]|?
  local function get_values(selected, allow_multiple)
    if not selected then
      return
    end

    local values = vim.tbl_map(function(k)
      return display_to_value_map[k]
    end, selected)

    values = vim.tbl_filter(function(v)
      return v ~= nil
    end, values)

    if #values > 1 and not allow_multiple then
      log.err "This mapping does not allow multiple entries"
      return
    end

    if #values > 0 then
      return values
    else
      return nil
    end
  end

  local actions = {
    default = function(selected)
      if not opts.on_choice then
        return
      end

      local values = get_values(selected, opts.allow_multiple)
      if not values then
        return
      end

      opts.on_choice(values)
    end,
  }

  if opts.selection_mappings then
    for key, mapping in pairs(opts.selection_mappings) do
      actions[format_keymap(key)] = function(selected)
        local values = get_values(selected, mapping.allow_multiple)
        if not values then
          return
        end

        values = vim.tbl_map(function(value)
          if type(value) == "string" then
            return { value = value, user_data = value, text = value }
          else
            return value
          end
        end, values)

        mapping.callback(unpack(values))
      end
    end
  end

  return actions
end

---@param opts obsidian.PickerFindOpts|? Options.
M.find_files = function(opts)
  opts = opts or {}
  local callback = opts.callback or function(path)
    api.open_note(path)
  end

  ---@type obsidian.Path
  local dir = opts.dir and Path.new(opts.dir) or Obsidian.dir

  require("fzf-lua").files {
    query = opts.query,
    cwd = tostring(dir),
    cmd = table.concat(search.build_find_cmd(nil, nil, { include_non_markdown = opts.include_non_markdown }), " "),
    cwd_prompt = false,
    prompt = format_prompt(opts.prompt_title),
    show_details = true,
    actions = get_selection_actions({
      callback = callback,
      no_default_mappings = opts.no_default_mappings,
      selection_mappings = opts.selection_mappings,
      query_mappings = opts.query_mappings,
    }, true),
  }
end

---@param opts obsidian.PickerGrepOpts|? Options.
M.grep = function(opts)
  opts = opts and opts or {}

  local fzf = require "fzf-lua"

  ---@type obsidian.Path
  local dir = opts.dir and Path.new(opts.dir) or Obsidian.dir
  local cmd = table.concat(search.build_grep_cmd(), " ")
  local actions = get_selection_actions {
    no_default_mappings = opts.no_default_mappings,
    selection_mappings = opts.selection_mappings,
    query_mappings = opts.query_mappings,
  }

  if opts.query and string.len(opts.query) > 0 then
    fzf.grep {
      cwd = tostring(dir),
      search = opts.query,
      cmd = cmd,
      actions = actions,
      prompt = format_prompt(opts.prompt_title),
    }
  else
    fzf.live_grep {
      cwd = tostring(dir),
      cmd = cmd,
      actions = actions,
      prompt = format_prompt(opts.prompt_title),
    }
  end
end

---@param values any[]
---@param opts obsidian.PickerSelectOpts|? Options.
---@param on_choice fun(choices: any[])|?
M.select = function(values, opts, on_choice)
  Picker.state.calling_bufnr = vim.api.nvim_get_current_buf()

  opts = opts or {}
  on_choice = on_choice or function() end

  ---@type table<string, any>
  local display_to_value_map = {}
  local file_preview = false
  for _, value in ipairs(values) do
    if type(value) == "table" and value.filename ~= nil then
      file_preview = true
      break
    end
  end

  ---@type string[]
  local entries = {}
  for _, value in ipairs(values) do
    local display
    if type(value) == "string" then
      display = value
    else
      display = opts.format_item and opts.format_item(value) or ut.make_display(value)
    end
    if type(value) ~= "table" or value.valid ~= false then
      display_to_value_map[display] = value
      entries[#entries + 1] = display
    end
  end

  local builtin = require "fzf-lua.previewer.builtin"
  local previewer

  if opts.preview_item then
    previewer = builtin.buffer_or_file:extend()

    function previewer:new(o, previewer_opts, fzf_win)
      previewer.super.new(self, o, previewer_opts, fzf_win)
      setmetatable(self, previewer)
      return self
    end

    function previewer.parse_entry(_self, entry_str)
      return ut.preview_spec_to_fzf_entry(opts.preview_item(display_to_value_map[entry_str]))
    end
  elseif file_preview then
    previewer = builtin.buffer_or_file:extend()

    function previewer:new(o, previewer_opts, fzf_win)
      previewer.super.new(self, o, previewer_opts, fzf_win)
      setmetatable(self, previewer)
      return self
    end

    function previewer.parse_entry(_self, entry_str)
      local entry = display_to_value_map[entry_str]
      return {
        path = entry.filename,
        line = entry.lnum,
        col = entry.col,
      }
    end
  end

  require("fzf-lua").fzf_exec(entries, {
    query = opts.query,
    previewer = previewer,
    prompt = format_prompt(
      ut.build_prompt { prompt_title = opts.prompt, selection_mappings = opts.selection_mappings }
    ),
    multi = opts.allow_multiple or nil,
    actions = get_value_actions(display_to_value_map, {
      on_choice = on_choice,
      allow_multiple = opts.allow_multiple,
      selection_mappings = opts.selection_mappings,
    }),
  })
end

return M
