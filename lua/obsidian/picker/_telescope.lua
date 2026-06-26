---@diagnostic disable: unresolved-require
local api = require "obsidian.api"
local search = require "obsidian.search"
local Path = require "obsidian.path"
local log = require "obsidian.log"
local Picker = require "obsidian.picker"
local ut = require "obsidian.picker.util"

local M = {}

---@param prompt_bufnr integer
---@param keep_open boolean|?
---@return table|?
local function get_entry(prompt_bufnr, keep_open)
  local entry = require("telescope.actions.state").get_selected_entry()
  if entry and not keep_open then
    require("telescope.actions").close(prompt_bufnr)
  end
  return entry
end

---@param prompt_bufnr integer
---@param keep_open boolean|?
---@param allow_multiple boolean|?
---@return obsidian.PickerEntry[]?
local function get_selected(prompt_bufnr, keep_open, allow_multiple)
  ---@return obsidian.PickerEntry
  local function selection_to_entry(selection)
    if selection.obsidian_item ~= nil then
      if type(selection.obsidian_item) == "table" then
        return selection.obsidian_item
      else
        return {
          value = selection.obsidian_item,
          user_data = selection.obsidian_item,
          text = tostring(selection.obsidian_item),
        }
      end
    end

    local raw = selection.raw
    local value = selection.value
    local filename = selection.path or selection.filename
    if filename == nil and type(value) == "table" then
      filename = value.path or value.filename
    end
    local user_data
    if raw and raw.user_data ~= nil then
      user_data = raw.user_data
    elseif filename == nil then
      user_data = value
    end

    return {
      filename = filename,
      lnum = selection.lnum,
      col = selection.col,
      user_data = user_data,
      text = raw and raw.text or selection.text or selection[1],
    }
  end

  local picker = require("telescope.actions.state").get_current_picker(prompt_bufnr)
  local entries = picker:get_multi_selection()
  if entries and #entries > 0 then
    if #entries > 1 and not allow_multiple then
      log.err "This mapping does not allow multiple entries"
      return
    end

    if not keep_open then
      require("telescope.actions").close(prompt_bufnr)
    end

    return vim.tbl_map(selection_to_entry, entries)
  else
    local entry = get_entry(prompt_bufnr, keep_open)

    if entry then
      return vim.tbl_map(selection_to_entry, { entry })
    end
  end
end

---@param prompt_bufnr integer
---@param keep_open boolean|?
---@param initial_query string|?
---@return string|?
local function get_query(prompt_bufnr, keep_open, initial_query)
  local query = require("telescope.actions.state").get_current_line()
  if not query or string.len(query) == 0 then
    query = initial_query
  end
  if query and string.len(query) > 0 then
    if not keep_open then
      require("telescope.actions").close(prompt_bufnr)
    end
    return query
  else
    return nil
  end
end

---@param opts { callback: (fun(entry: obsidian.PickerEntry, ...: obsidian.PickerEntry))|?, allow_multiple: boolean|?, query_mappings: obsidian.PickerMappingTable|?, selection_mappings: obsidian.PickerMappingTable|?, initial_query: string|? }
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
          local entry = entries[1]
          if entry then
            ---@diagnostic disable-next-line: param-type-mismatch
            mapping.callback(entry, unpack(entries, 2))
          end
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
      if entries then
        local entry = entries[1]
        if entry then
          ---@diagnostic disable-next-line: param-type-mismatch
          opts.callback(entry, unpack(entries, 2))
        end
      end
    end)
  end
end

---@param opts obsidian.PickerFindOpts|? Options.
M.find_files = function(opts)
  opts = opts or {}
  local callback = opts.callback or function(path)
    api.open_note(path)
  end

  local prompt_title = ut.build_prompt {
    prompt_title = opts.prompt_title,
    query_mappings = opts.query_mappings,
    selection_mappings = opts.selection_mappings,
  }

  require("telescope.builtin").find_files {
    default_text = opts.query,
    prompt_title = prompt_title,
    cwd = opts.dir and tostring(opts.dir) or tostring(Obsidian.dir),
    find_command = search.build_find_cmd(nil, nil, { include_non_markdown = opts.include_non_markdown }),
    attach_mappings = function(_, map)
      attach_picker_mappings(map, {
        callback = function(entry)
          if entry.filename then
            callback(entry.filename)
          end
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
    require("telescope.builtin").grep_string {
      prompt_title = prompt_title,
      cwd = tostring(cwd),
      vimgrep_arguments = search.build_grep_cmd(),
      search = opts.query,
      attach_mappings = attach_mappings,
    }
  else
    require("telescope.builtin").live_grep {
      prompt_title = prompt_title,
      cwd = tostring(cwd),
      vimgrep_arguments = search.build_grep_cmd(),
      attach_mappings = attach_mappings,
    }
  end
end

---@param values any[]
---@param opts obsidian.PickerSelectOpts|? Options.
---@param on_choice fun(choices: any[])|?
M.select = function(values, opts, on_choice)
  local pickers = require "telescope.pickers"
  local finders = require "telescope.finders"
  local conf = require "telescope.config"

  Picker.state.calling_bufnr = vim.api.nvim_get_current_buf()

  opts = opts and opts or {}
  on_choice = on_choice or function() end

  ---@param prompt_bufnr integer
  ---@return any[]?
  local function get_selected_values(prompt_bufnr)
    local picker = require("telescope.actions.state").get_current_picker(prompt_bufnr)
    local entries = picker:get_multi_selection()
    if not entries or #entries == 0 then
      local entry = get_entry(prompt_bufnr, false)
      entries = entry and { entry } or {}
    elseif #entries > 1 and not opts.allow_multiple then
      log.err "This mapping does not allow multiple entries"
      return
    else
      require("telescope.actions").close(prompt_bufnr)
    end

    return vim.tbl_map(function(entry)
      return entry.obsidian_item
    end, entries)
  end

  local picker_opts = {
    default_text = opts.query,
    attach_mappings = function(_, map)
      attach_picker_mappings(map, {

        query_mappings = opts.query_mappings,
        selection_mappings = opts.selection_mappings,
      })

      map({ "i", "n" }, "<CR>", function(prompt_bufnr)
        local choices = get_selected_values(prompt_bufnr)
        if choices then
          on_choice(choices)
        end
      end)
      return true
    end,
  }

  local prompt_title = ut.build_prompt {
    prompt_title = opts.prompt,
    query_mappings = opts.query_mappings,
    selection_mappings = opts.selection_mappings,
  }

  local previewer
  if opts.preview_item then
    previewer = require("telescope.previewers").new_buffer_previewer {
      define_preview = function(self, entry)
        local spec = opts.preview_item(entry.obsidian_item)
        vim.schedule(function()
          if self.state and self.state.winid then
            ut.show_preview_spec(self.state.winid, spec)
          end
        end)
      end,
    }
  elseif vim.iter(values):any(function(value)
    return type(value) == "table" and value.filename ~= nil
  end) then
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

  pickers
    .new(picker_opts, {
      prompt_title = prompt_title,
      finder = finders.new_table {
        results = values,
        entry_maker = function(v)
          local display
          if opts.format_item then
            display = opts.format_item(v)
          elseif type(v) == "string" then
            display = v
          else
            display = ut.make_display(v)
          end

          local ordinal = display
          if type(v) == "table" and v.ordinal ~= nil then
            ordinal = v.ordinal
          elseif type(v) == "table" and v.filename ~= nil then
            ordinal = ordinal .. " " .. v.filename
          end

          return {
            value = type(v) == "table" and v.user_data or v,
            display = function()
              return display
            end,
            ordinal = ordinal,
            filename = type(v) == "table" and v.filename or nil,
            lnum = type(v) == "table" and v.lnum or nil,
            col = type(v) == "table" and v.col or nil,
            obsidian_item = v,
          }
        end,
      },
      sorter = conf.values.generic_sorter(picker_opts),
      previewer = previewer,
    })
    :find()
end

return M
