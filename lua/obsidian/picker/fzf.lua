---@diagnostic disable: unresolved-require
local log = require "obsidian.log"
local Picker = require "obsidian.picker"
local ut = require "obsidian.picker.util"
local api = require "obsidian.api"

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

---@return table|?
local function builtin_previewer_winopts()
  local ok, config = pcall(require, "fzf-lua.config")
  if not ok or type(config.globals.winopts) ~= "table" then
    return
  end

  local preview = config.globals.winopts.preview
  local border = type(preview) == "table" and preview.border or nil
  if type(border) ~= "function" then
    return
  end

  local info = debug.getinfo(border, "S")
  -- The fzf-tmux profile's border function only accepts native previewers.
  -- Use a Neovim border for our builtin buffer previewer instead.
  if info and info.source and string.find(info.source, "fzf%-tmux%.lua") then
    return { preview = { border = "rounded" } }
  end
end

--- Register Obsidian workspace providers with fzf-lua.
M.setup = function()
  local fzf = require "fzf-lua"

  fzf.register_extension("obsidian_files", function(opts)
    opts = opts or {}
    opts.cwd = tostring(api.resolve_workspace_dir())
    return fzf.files(opts)
  end, {}, true)

  fzf.register_extension("obsidian_grep", function(opts)
    opts = opts or {}
    opts.cwd = tostring(api.resolve_workspace_dir())
    return fzf.live_grep(opts)
  end, {}, true)
end

---@param opts { callback: (fun(selections: any[]))|?, no_default_mappings: boolean|?, selection_mappings: obsidian.PickerMappingTable|?, query_mappings: obsidian.PickerMappingTable|? }
---@param path_only? boolean HACK:
local function get_selection_actions(opts, path_only)
  local entry_to_file = require("fzf-lua.path").entry_to_file

  local function get_entries(selected, fzf_opts, paths_only)
    return vim.tbl_map(function(selection)
      local file = entry_to_file(selection, fzf_opts)
      if paths_only then
        return file.path
      else
        return {
          filename = file.path,
          lnum = file.line and file.line > 0 and file.line or nil,
          col = file.col and file.col > 0 and file.col or nil,
        }
      end
    end, selected or {})
  end

  local actions = {
    default = function(selected, fzf_opts)
      if opts.callback then
        opts.callback(get_entries(selected, fzf_opts, path_only))
      elseif not opts.no_default_mappings then
        require("fzf-lua.actions").file_edit_or_qf(selected, fzf_opts)
      end
    end,
  }

  if opts.selection_mappings then
    for key, mapping in pairs(opts.selection_mappings) do
      actions[format_keymap(key)] = function(selected, fzf_opts)
        if mapping.quickfix then
          -- fzf-lua reports marked rows or the current row, but not the filtered result set.
          ut.send_to_qf(get_entries(selected, fzf_opts, false), mapping.quickfix)
          require("obsidian.preview").cleanup_unshown()
          return
        end
        local paths = get_entries(selected, fzf_opts, true)
        if #paths > 1 and not mapping.allow_multiple then
          log.err "This mapping does not allow multiple entries"
          return
        end
        require("obsidian.preview").cleanup_unshown()
        mapping.callback(unpack(paths))
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

---@param entries string[]
---@param query string
---@param fzf_opts table|?
---@return string[]|?
local function get_filtered_entries(entries, query, fzf_opts)
  if query == "" then
    return vim.list_extend({}, entries)
  end

  local command = { (fzf_opts and fzf_opts.fzf_bin) or "fzf", "--filter", query }
  local all_opts = fzf_opts and fzf_opts.fzf_opts or {}
  local option_names = {
    "--delimiter",
    "--with-nth",
    "--nth",
    "--algo",
    "--case-sensitive",
    "--ignore-case",
    "--smart-case",
    "--no-sort",
    "--tiebreak",
    "--scheme",
    "--exact",
    "--extended",
    "--no-extended",
    "--literal",
    "--ansi",
  }
  for _, name in ipairs(option_names) do
    local value = all_opts[name]
    if value == nil then
      value = name == "--delimiter" and "\t" or name == "--with-nth" and "2.." or nil
    end
    if value ~= nil and value ~= false then
      command[#command + 1] = name
      if type(value) ~= "boolean" then
        command[#command + 1] = tostring(value)
      end
    end
  end

  local ok, process = pcall(vim.system, command, { stdin = table.concat(entries, "\n"), text = true })
  if not ok then
    log.err("Failed to query filtered fzf results: %s", process)
    return
  end
  local result = process:wait(5000)
  if not result or (result.code ~= 0 and result.code ~= 1) then
    log.err "Failed to query filtered fzf results"
    return
  end

  return vim.split((result.stdout or ""):gsub("\r", ""), "\n", { plain = true, trimempty = true })
end

---@param entry_to_value_map table<string, any>
---@param opts { on_choice: fun(choices: any[])|?, allow_multiple: boolean|?, selection_mappings: obsidian.PickerMappingTable|?, query_mappings: obsidian.PickerMappingTable|?, entries: string[], marked_ids: table<string, boolean>, initial_query: string? }
local function get_value_actions(entry_to_value_map, opts)
  ---@param allow_multiple boolean|?
  ---@return any[]|?
  local function get_values(selected, allow_multiple)
    if not selected then
      return
    end

    local values = vim.tbl_map(function(k)
      return entry_to_value_map[k]
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
      require("obsidian.preview").cleanup_unshown()
    end,
  }

  if opts.selection_mappings then
    for key, mapping in pairs(opts.selection_mappings) do
      if mapping then
        actions[format_keymap(key)] = function(selected, fzf_opts)
          if mapping.quickfix then
            local marked_ids = vim.deepcopy(opts.marked_ids or {})
            if (not next(marked_ids)) and selected and #selected > 1 then
              for _, entry in ipairs(selected) do
                local id = entry:match "^(%d+)\t"
                if id then
                  marked_ids[id] = true
                end
              end
            end

            local fzf = require "fzf-lua"
            local query = fzf_opts and fzf_opts.query
            if type(fzf.get_last_query) == "function" then
              local last_query = fzf.get_last_query()
              if type(last_query) == "string" then
                query = last_query
              end
            end
            query = type(query) == "string" and query or opts.initial_query or ""
            local filtered = get_filtered_entries(opts.entries or {}, query, fzf_opts) or {}
            local values, included = {}, {}
            for _, entry in ipairs(filtered) do
              local id = entry:match "^(%d+)\t"
              if not next(marked_ids) or (id and marked_ids[id]) then
                values[#values + 1] = entry_to_value_map[entry]
                if id then
                  included[id] = true
                end
              end
            end
            for _, entry in ipairs(opts.entries or {}) do
              local id = entry:match "^(%d+)\t"
              if id and marked_ids[id] and not included[id] then
                values[#values + 1] = entry_to_value_map[entry]
              end
            end
            ut.send_to_qf(values, mapping.quickfix)
            require("obsidian.preview").cleanup_unshown()
            return
          end
          local values = get_values(selected, mapping.allow_multiple)
          if not values then
            return
          end

          require("obsidian.preview").cleanup_unshown()
          mapping.callback(unpack(values))
        end
      end
    end
  end

  if opts.query_mappings then
    for key, mapping in pairs(opts.query_mappings) do
      if mapping then
        actions[format_keymap(key)] = function(_, fzf_opts)
          require("obsidian.preview").cleanup_unshown()
          mapping.callback(fzf_opts.query)
        end
      end
    end
  end

  return actions
end

---@param opts obsidian.PickerGrepOpts Options.
M.grep = function(opts)
  vim.validate("opts", opts, "table")

  local fzf = require "fzf-lua"

  local cmd = table.concat(opts.cmd, " ")
  local actions = get_selection_actions {
    callback = opts.callback or ut.open_notes,
    no_default_mappings = opts.no_default_mappings,
    selection_mappings = opts.selection_mappings,
    query_mappings = opts.query_mappings,
  }

  if opts.query and string.len(opts.query) > 0 then
    fzf.grep {
      cwd = tostring(opts.dir),
      search = opts.query,
      cmd = cmd,
      actions = actions,
      prompt = format_prompt(opts.prompt_title),
    }
  else
    fzf.live_grep {
      cwd = tostring(opts.dir),
      cmd = cmd,
      actions = actions,
      prompt = format_prompt(opts.prompt_title),
    }
  end
end

---@param opts obsidian.PickerSelectOpts
---@return boolean
local function needs_multi(opts)
  if opts.allow_multiple then
    return true
  end

  for _, mapping in pairs(opts.selection_mappings or {}) do
    if mapping and mapping.allow_multiple then
      return true
    end
  end

  return false
end

---@param spec obsidian.ui_select_preview_spec|?
---@return table
local preview_spec_to_fzf_entry = function(spec)
  if not spec then
    return {}
  end

  local pos = spec.pos or { 1, 0 }
  local pos_end = spec.pos_end
  return {
    _scratch_buf = spec.buf,
    line = pos[1] or 1,
    col = (pos[2] or 0) + 1,
    end_line = pos_end and pos_end[1] or nil,
    end_col = pos_end and (pos_end[2] or 0) + 1 or nil,
  }
end

---@param values any[]
---@param opts obsidian.PickerSelectOpts|? Options.
---@param on_choice fun(choices: any[])|?
M.select = function(values, opts, on_choice)
  Picker.state.calling_bufnr = vim.api.nvim_get_current_buf()

  opts = opts or {}
  on_choice = on_choice or function() end

  ---@type table<string, any>
  local entry_to_value_map = {}

  ---@type string[]
  local entries = {}
  for idx, value in ipairs(values) do
    local display = opts.format_item and opts.format_item(value) or ut.make_display(value)
    local entry = ("%d\t%s"):format(idx, display)
    entry_to_value_map[entry] = value
    entries[#entries + 1] = entry
  end

  local builtin = require "fzf-lua.previewer.builtin"
  ---@type table
  local previewer

  if opts.preview_item then
    previewer = builtin.buffer_or_file:extend()

    function previewer:new(o, previewer_opts, fzf_win)
      previewer.super.new(self, o, previewer_opts, fzf_win)
      setmetatable(self, previewer)
      return self
    end

    function previewer.parse_entry(_self, entry_str)
      return preview_spec_to_fzf_entry(opts.preview_item(entry_to_value_map[entry_str]))
    end
  end

  local marked_ids = {}
  local has_quickfix_mapping = false
  for _, mapping in pairs(opts.selection_mappings or {}) do
    if mapping and mapping.quickfix then
      has_quickfix_mapping = true
      break
    end
  end
  local keymap
  if has_quickfix_mapping then
    local function transform_binding(action, clear_marks)
      local transform = require("fzf-lua.shell").stringify_data(function(items)
        if clear_marks then
          for id in pairs(marked_ids) do
            marked_ids[id] = nil
          end
        else
          local entry = items and items[1]
          local id = type(entry) == "string" and entry:match "^(%d+)\t" or nil
          if id then
            marked_ids[id] = not marked_ids[id] or nil
          end
        end
        return action
      end, {}, "{}")
      return "transform:" .. transform
    end
    keymap = {
      fzf = {
        tab = transform_binding "toggle+down",
        btab = transform_binding "toggle+up",
        ["ctrl-i"] = transform_binding "toggle+down",
        ["alt-a"] = transform_binding("toggle-all", true),
      },
    }
  end
  local allow_multiple = needs_multi(opts)
  local winopts = previewer and builtin_previewer_winopts() or {}
  local ok, config = pcall(require, "fzf-lua.config")
  local user_on_close = ok and config.globals.winopts and config.globals.winopts.on_close or nil
  winopts = vim.tbl_extend("force", {}, winopts or {}, {
    on_close = function(...)
      if type(user_on_close) == "function" then
        pcall(user_on_close, ...)
      end
      require("obsidian.preview").cleanup_unshown()
    end,
  })
  require("fzf-lua").fzf_exec(entries, {
    query = opts.query,
    keymap = keymap,
    previewer = previewer,
    winopts = winopts,
    prompt = format_prompt(ut.build_prompt {
      prompt_title = opts.prompt,
      query_mappings = opts.query_mappings,
      selection_mappings = opts.selection_mappings,
    }),
    fzf_opts = {
      ["--delimiter"] = "\t",
      ["--with-nth"] = "2..",
      ["--multi"] = allow_multiple,
      ["--no-multi"] = not allow_multiple,
    },
    actions = get_value_actions(entry_to_value_map, {
      on_choice = on_choice,
      allow_multiple = opts.allow_multiple,
      selection_mappings = opts.selection_mappings,
      query_mappings = opts.query_mappings,
      entries = entries,
      marked_ids = marked_ids,
      initial_query = opts.query,
    }),
  })
end

return M
