---@diagnostic disable: unresolved-require
local search = require "obsidian.search"
local Picker = require "obsidian.picker"
local Path = require "obsidian.path"
local ut = require "obsidian.picker.util"
local api = require "obsidian.api"

--- Build snacks pick opts (keymaps + actions) for query-style mappings. The
--- callback receives the currently typed query string, mirroring the behavior
--- of the telescope/fzf integrations.
---
---@param mapping obsidian.PickerMappingTable|?
---@param live boolean Whether the picker runs in live mode (grep). When true
---  the query is read from `picker.input.filter.search`, otherwise from
---  `picker.input.filter.pattern`.
---@return table
local function query_mappings(mapping, live)
  if type(mapping) ~= "table" then
    return {}
  end
  local opts = {
    win = {
      input = {
        keys = {},
      },
    },
    actions = {},
  }
  for k, v in pairs(mapping) do
    local name = "obsidian_query_" .. string.gsub(v.desc, " ", "_")
    ---@diagnostic disable-next-line: assign-type-mismatch
    opts.win.input.keys[k] = { name, mode = { "n", "i" }, desc = v.desc }
    opts.actions[name] = function(picker)
      local query = live and picker.input.filter.search or picker.input.filter.pattern
      picker:close()
      vim.schedule(function()
        v.callback(query)
      end)
    end
  end
  return opts
end

---@param mapping obsidian.PickerMappingTable|?
---@param selection_value fun(item: table): any
---@return table
local function notes_mappings(mapping, selection_value)
  if type(mapping) == "table" then
    local opts = {
      win = {
        input = {
          keys = {
            ["q"] = "cancel",
          },
        },
        list = {
          keys = {
            ["q"] = "cancel",
          },
        },
        preview = {
          keys = {
            ["q"] = "cancel",
          },
        },
      },
      actions = {},
    }
    for k, v in pairs(mapping) do
      local name = string.gsub(v.desc, " ", "_")
      ---@diagnostic disable-next-line: assign-type-mismatch
      opts.win.input.keys[k] = { name, mode = { "n", "i" }, desc = v.desc }
      opts.actions[name] = function(picker, item)
        picker:close()
        if v.allow_multiple then
          local selected = picker:selected { fallback = true }
          local values = vim.tbl_map(selection_value, selected)
          vim.schedule(function()
            v.callback(unpack(values))
          end)
        else
          local value = selection_value(item)
          vim.schedule(function()
            v.callback(value)
          end)
        end
      end
    end
    return opts
  end
  return {}
end

local M = {}

--- Register Obsidian workspace sources with snacks.picker.
---
--- This is intentionally opt-in. Requiring obsidian.nvim does not alter Snacks'
--- source registry or its `vim.ui.select` implementation.
M.setup = function()
  local sources = require "snacks.picker.config.sources"

  ---@param name string
  ---@param source table
  local function register(name, source)
    local configure = source.config
    source.config = function(source_opts)
      if configure then
        source_opts = configure(source_opts) or source_opts
      end
      source_opts.cwd = tostring(api.resolve_workspace_dir())
      return source_opts
    end
    sources[name] = source
  end

  register("obsidian_files", {
    title = "Obsidian Files",
    finder = "files",
    format = "file",
    show_empty = true,
    supports_live = true,
  })

  register("obsidian_grep", {
    title = "Obsidian Grep",
    finder = "grep",
    format = "file",
    show_empty = true,
    live = true,
    supports_live = true,
  })
end

---@param opts obsidian.PickerGrepOpts|? Options.
M.grep = function(opts)
  opts = opts or {}

  ---@type obsidian.Path
  local dir = opts.dir and Path.new(opts.dir) or api.resolve_workspace_dir()
  local map = vim.tbl_deep_extend(
    "force",
    {},
    notes_mappings(opts.selection_mappings, function(item)
      return item._path or item.filename
    end),
    query_mappings(opts.query_mappings, true)
  )
  local callback = opts.callback or ut.open_notes

  local args = search.build_grep_cmd()
  local cmd = table.remove(args, 1)

  local pick_opts = vim.tbl_extend("force", map or {}, {
    search = opts.query,
    source = "grep",
    title = opts.prompt_title,
    cwd = tostring(dir),
    cmd = cmd,
    args = args,
    confirm = function(picker)
      local selected = picker:selected { fallback = true }
      picker:close()
      callback(vim.tbl_map(function(item)
        return {
          filename = item._path or item.filename,
          col = item.pos and item.pos[2] + 1,
          lnum = item.pos and item.pos[1],
          user_data = item.value,
        }
      end, selected))
    end,
  })
  require("snacks.picker").pick(pick_opts)
end

---@param values any[]
---@param opts obsidian.PickerSelectOpts|? Options.
---@param on_choice fun(choices: any[])|?
M.select = function(values, opts, on_choice)
  Picker.state.calling_bufnr = vim.api.nvim_get_current_buf()

  opts = opts or {}
  on_choice = on_choice or function() end

  local entries = {}
  for _, value in ipairs(values) do
    local display = opts.format_item and opts.format_item(value) or ut.make_display(value)
    table.insert(entries, {
      text = display,
      obsidian_item = value,
    })
  end

  local map = vim.tbl_deep_extend(
    "force",
    {},
    notes_mappings(opts.selection_mappings, function(item)
      return item.obsidian_item
    end),
    query_mappings(opts.query_mappings, false)
  )

  local previewer
  if opts.preview_item then
    previewer = function(ctx)
      ctx.preview:reset()
      local spec = opts.preview_item(ctx.item.obsidian_item)
      ctx.item.buf = spec.buf
      ctx.item.pos = spec.pos
      ctx.item.end_pos = spec.pos_end
      ctx.preview:set_title(ctx.item.text)
      ctx.preview:set_buf(spec.buf)
      ctx.preview:highlight { buf = spec.buf }
      ctx.preview:loc()
    end
  end

  local pick_opts = vim.tbl_extend("force", map or {}, {
    title = opts.prompt,
    pattern = opts.query,
    items = entries,
    preview = previewer,
    layout = {
      preview = opts.preview_item ~= nil,
      preset = "default",
    },
    format = "text",
    confirm = function(picker, item)
      local selected = opts.allow_multiple and picker:selected { fallback = true } or (item and { item } or {})
      picker:close()
      on_choice(vim.tbl_map(function(selected_item)
        return selected_item.obsidian_item
      end, selected))
    end,
  })

  require("snacks.picker").pick(pick_opts)
end

return M
