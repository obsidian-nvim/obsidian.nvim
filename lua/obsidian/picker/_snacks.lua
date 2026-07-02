---@diagnostic disable: unresolved-require
local api = require "obsidian.api"
local search = require "obsidian.search"
local Picker = require "obsidian.picker"
local Path = require "obsidian.path"
local ut = require "obsidian.picker.util"

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
---@return table
local function notes_mappings(mapping)
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
          ---@type obsidian.PickerEntry[]
          local entries = {}
          for _, sel in ipairs(selected) do
            table.insert(entries, {
              filename = sel._path or sel.file,
              user_data = sel.value,
            })
          end
          vim.schedule(function()
            ---@diagnostic disable-next-line: param-type-mismatch
            v.callback(unpack(entries))
          end)
        else
          ---@type obsidian.PickerEntry
          local entry = {
            filename = item._path or item.file,
            user_data = item.value,
          }
          vim.schedule(function()
            v.callback(entry)
          end)
        end
      end
    end
    return opts
  end
  return {}
end

local M = {}

---@param opts obsidian.PickerFindOpts|? Options.
M.find_files = function(opts)
  opts = opts or {}
  local callback = opts.callback or api.open_note

  ---@type obsidian.Path
  local dir = opts.dir and Path.new(opts.dir) or Obsidian.dir

  local map = vim.tbl_deep_extend(
    "force",
    {},
    notes_mappings(opts.selection_mappings),
    query_mappings(opts.query_mappings, false)
  )

  local args = search.build_find_cmd(nil, nil, { include_non_markdown = opts.include_non_markdown })
  local cmd = table.remove(args, 1)

  local pick_opts = vim.tbl_extend("force", map or {}, {
    pattern = opts.query,
    source = "files",
    title = opts.prompt_title,
    cwd = tostring(dir),
    cmd = cmd,
    args = args,
    confirm = function(picker, item)
      picker:close()
      if item then
        callback(item._path)
      end
    end,
  })
  require("snacks.picker").pick(pick_opts)
end

---@param opts obsidian.PickerGrepOpts|? Options.
M.grep = function(opts)
  opts = opts or {}

  ---@type obsidian.Path
  local dir = opts.dir and Path.new(opts.dir) or Obsidian.dir
  local map =
    vim.tbl_deep_extend("force", {}, notes_mappings(opts.selection_mappings), query_mappings(opts.query_mappings, true))
  local callback = opts.callback or api.open_note

  local args = search.build_grep_cmd()
  local cmd = table.remove(args, 1)

  local pick_opts = vim.tbl_extend("force", map or {}, {
    search = opts.query,
    source = "grep",
    title = opts.prompt_title,
    cwd = tostring(dir),
    cmd = cmd,
    args = args,
    confirm = function(picker, item)
      picker:close()
      if item then
        callback {
          filename = item._path or item.filename,
          col = item.pos and item.pos[2] + 1,
          lnum = item.pos and item.pos[1],
          user_data = item.value,
        }
      end
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

  ---@diagnostic disable-next-line: redundant-parameter
  local has_preview = opts.preview_item ~= nil
    ---@diagnostic disable-next-line: call-non-callable
    or vim.iter(values):any(function(value)
      return type(value) == "table" and value.filename ~= nil
    end)

  local entries = {}
  for _, value in ipairs(values) do
    local display
    if type(value) == "string" then
      display = value
    else
      display = opts.format_item and opts.format_item(value) or ut.make_display(value)
    end
    if type(value) ~= "table" or value.valid ~= false then
      ---@type obsidian.PickerEntry|string
      local picker_value = value
      table.insert(entries, {
        text = display,
        file = type(picker_value) == "table" and picker_value.filename or nil,
        value = type(picker_value) == "table" and picker_value.user_data or picker_value,
        pos = type(picker_value) == "table" and picker_value.lnum and {
          picker_value.lnum,
          picker_value.col and picker_value.col - 1 or 0,
        } or nil, -- from (1, 1) to (1, 0)
        end_pos = type(picker_value) == "table" and picker_value.end_lnum and {
          picker_value.end_lnum,
          picker_value.end_col and picker_value.end_col - 1 or 0,
        } or nil,
        dir = type(picker_value) == "table" and picker_value.filename and Path.new(picker_value.filename):is_dir()
          or false,
        obsidian_item = picker_value,
      })
    end
  end

  local map = vim.tbl_deep_extend(
    "force",
    {},
    notes_mappings(opts.selection_mappings),
    query_mappings(opts.query_mappings, false)
  )

  local previewer
  if opts.preview_item then
    previewer = function(ctx)
      ctx.preview:reset()
      local spec = opts.preview_item(ctx.item.obsidian_item)
      if not ut.valid_preview_spec(spec) then
        ctx.preview:notify("no preview available", "warn", { item = false })
        return
      end
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
      preview = has_preview,
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
