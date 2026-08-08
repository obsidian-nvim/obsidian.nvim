---@diagnostic disable: unresolved-require
local search = require "obsidian.search"
local Path = require "obsidian.path"
local log = require "obsidian.log"
local Picker = require "obsidian.picker"
local ut = require "obsidian.picker.util"
local Integration = require "obsidian.picker.integration"

local M = {}

local integration_opts = {}
local extension_loaded = false

---@class obsidian.picker.telescope.SetupOpts
---@field find_files? table telescope.builtin.find_files options.
---@field grep? table telescope.builtin.live_grep options.

--- Register the `obsidian` Telescope extension.
---@param opts obsidian.picker.telescope.SetupOpts|?
M.setup = function(opts)
  integration_opts = vim.deepcopy(opts or {})
  if not extension_loaded then
    ---@diagnostic disable-next-line: undefined-field
    require("telescope").load_extension "obsidian"
    extension_loaded = true
  end
end

--- Find files in the workspace active at invocation time.
---@param opts table|?
M.workspace_files = function(opts)
  return require("telescope.builtin").find_files(Integration.workspace_opts(integration_opts.find_files, opts))
end

--- Live-grep files in the workspace active at invocation time.
---@param opts table|?
M.workspace_grep = function(opts)
  return require("telescope.builtin").live_grep(Integration.workspace_opts(integration_opts.grep, opts))
end

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
---@return any[]?
local function get_selected(prompt_bufnr, keep_open, allow_multiple)
  ---@return any
  local function selection_to_entry(selection)
    if selection.obsidian_item ~= nil then
      return selection.obsidian_item
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

---@param opts { callback: (fun(entries: obsidian.PickerEntry[]))|?, query_mappings: obsidian.PickerMappingTable|?, selection_mappings: obsidian.PickerMappingTable|?, selection_value: (fun(entry: any): string)|?, initial_query: string|? }
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
          local values = opts.selection_value and vim.tbl_map(opts.selection_value, entries) or entries
          local value = values[1]
          if value then
            mapping.callback(value, unpack(values, 2))
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
      local entries = get_selected(prompt_bufnr, false, true)
      if entries and #entries > 0 then
        opts.callback(entries)
      end
    end)
  end
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
      callback = opts.callback or ut.open_notes,
      query_mappings = opts.query_mappings,
      selection_mappings = opts.selection_mappings,
      selection_value = function(entry)
        return entry.filename
      end,
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
          else
            display = ut.make_display(v)
          end

          return {
            value = v,
            display = function()
              return display
            end,
            ordinal = display,
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
