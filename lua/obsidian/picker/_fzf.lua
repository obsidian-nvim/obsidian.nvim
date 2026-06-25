local api = require "obsidian.api"
local search = require "obsidian.search"
local Path = require "obsidian.path"
local log = require "obsidian.log"
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

---@param opts { callback: fun(selection: obsidian.PickerEntry)|?, query_mappings: obsidian.PickerMappingTable|? }
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
      else
        require("fzf-lua.actions").file_edit_or_qf(selected, fzf_opts)
      end
    end,
  }

  if opts.query_mappings then
    for key, mapping in pairs(opts.query_mappings) do
      actions[format_keymap(key)] = function(_, fzf_opts)
        local query = fzf_opts.query
        if query and string.len(query) > 0 then
          mapping.callback(query)
        end
      end
    end
  end

  return actions
end

---@param display_to_value_map table<string, any>
---@param opts { callback: fun(path: string)|?, allow_multiple: boolean|?, query_mappings: obsidian.PickerMappingTable|? }
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
      if not opts.callback then
        return
      end

      local values = get_values(selected, opts.allow_multiple)
      if not values then
        return
      end

      opts.callback(unpack(values))
    end,
  }

  if opts.query_mappings then
    for key, mapping in pairs(opts.query_mappings) do
      actions[format_keymap(key)] = function(_, fzf_opts)
        local query = fzf_opts.query
        if query and string.len(query) > 0 then
          mapping.callback(query)
        end
      end
    end
  end

  return actions
end

---@param opts obsidian.PickerFindOpts|? Options.
M.find_files = function(opts)
  opts = opts or {}
  opts.callback = opts.callback or api.open_note

  ---@type obsidian.Path
  local dir = opts.dir and Path.new(opts.dir) or Obsidian.dir

  local _, _, class = require("fzf-lua").files {
    query = opts.query,
    cwd = tostring(dir),
    cmd = table.concat(search.build_find_cmd(nil, nil, { include_non_markdown = opts.include_non_markdown }), " "),
    cwd_prompt = false,
    prompt = format_prompt(ut.build_prompt { prompt_title = opts.prompt_title, query_mappings = opts.query_mappings }),
    show_details = true,
    actions = get_selection_actions({
      callback = opts.callback,
      query_mappings = opts.query_mappings,
    }, true),
  }
  return class
end

---@param opts obsidian.PickerGrepOpts|? Options.
M.grep = function(opts)
  opts = opts and opts or {}

  local fzf = require "fzf-lua"

  ---@type obsidian.Path
  local dir = opts.dir and Path.new(opts.dir) or Obsidian.dir
  local cmd = table.concat(search.build_grep_cmd(), " ")
  local actions = get_selection_actions {
    query_mappings = opts.query_mappings,
  }
  local prompt =
    format_prompt(ut.build_prompt { prompt_title = opts.prompt_title, query_mappings = opts.query_mappings })

  if opts.query and string.len(opts.query) > 0 then
    fzf.grep {
      cwd = tostring(dir),
      search = opts.query,
      cmd = cmd,
      actions = actions,
      prompt = prompt,
    }
  else
    fzf.live_grep {
      cwd = tostring(dir),
      cmd = cmd,
      actions = actions,
      prompt = prompt,
    }
  end
end

---@param values string[]|obsidian.PickerEntry[]
---@param opts obsidian.PickerPickOpts|? Options.
M.pick = function(values, opts)
  opts = opts or {}
  opts.callback = opts.callback or api.open_note

  ---@type table<string, any>
  local display_to_value_map = {}
  local file_preview = vim.iter(values):any(function(v)
    return type(v) == "table" and v.filename ~= nil
  end)

  ---@type string[]
  local entries = {}
  for _, value in ipairs(values) do
    local display
    if type(value) == "string" then
      display = value
      value = { user_data = value }
    else
      display = opts.format_item and opts.format_item(value) or ut.make_display(value)
    end
    if value.valid ~= false then
      display_to_value_map[display] = value
      entries[#entries + 1] = display
    end
  end

  local builtin = require "fzf-lua.previewer.builtin"

  local MyPreviewer = builtin.buffer_or_file:extend()

  function MyPreviewer:new(o, previewer_opts, fzf_win)
    MyPreviewer.super.new(self, o, previewer_opts, fzf_win)
    setmetatable(self, MyPreviewer)
    return self
  end

  function MyPreviewer.parse_entry(_self, entry_str)
    local entry = display_to_value_map[entry_str]
    return {
      path = entry.filename,
      line = entry.lnum,
      col = entry.col and entry.col + 1,
    }
  end

  require("fzf-lua").fzf_exec(entries, {
    previewer = file_preview and MyPreviewer or nil,
    prompt = format_prompt(ut.build_prompt { prompt_title = opts.prompt_title, query_mappings = opts.query_mappings }),
    actions = get_value_actions(display_to_value_map, {
      callback = opts.callback,
      allow_multiple = opts.allow_multiple,
      query_mappings = opts.query_mappings,
    }),
  })
end

return M
