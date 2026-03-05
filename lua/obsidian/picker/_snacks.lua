local snacks_picker = require "snacks.picker"

local obsidian = require "obsidian"
local search = obsidian.search
local Picker = obsidian.Picker
local Path = obsidian.Path
local ut = require "obsidian.picker.util"

---@param mapping table
---@return table
local function notes_mappings(mapping)
  if type(mapping) == "table" then
    local opts = { win = { input = { keys = {} } }, actions = {} }
    for k, v in pairs(mapping) do
      local name = string.gsub(v.desc, " ", "_")
      opts.win.input.keys[k] = { name, mode = { "n", "i" }, desc = v.desc }
      opts.actions[name] = function(picker, item)
        picker:close()
        if v.allow_multiple then
          local selected = picker:selected { fallback = true }
          ---@type obsidian.PickerEntry[]
          local entries = {}
          for _, sel in ipairs(selected) do
            table.insert(entries, {
              filename = sel._path,
              user_data = sel.user_data or sel.value or sel.text,
            })
          end
          vim.schedule(function()
            v.callback(unpack(entries))
          end)
        else
          ---@type obsidian.PickerEntry
          local entry = {
            filename = item._path,
            user_data = item.user_data or item.value or item.text,
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
  opts.callback = opts.callback or obsidian.api.open_note

  ---@type obsidian.Path
  local dir = opts.dir.filename and Path.new(opts.dir.filename) or Obsidian.dir

  local map = vim.tbl_deep_extend("force", {}, notes_mappings(opts.selection_mappings))

  local args = search.build_find_cmd()
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
        opts.callback(item._path)
      end
    end,
  })
  snacks_picker.pick(pick_opts)
end

---@param opts obsidian.PickerGrepOpts|? Options.
M.grep = function(opts)
  opts = opts or {}

  ---@type obsidian.Path
  local dir = opts.dir.filename and Path.new(opts.dir.filename) or Obsidian.dir

  local map = vim.tbl_deep_extend("force", {}, notes_mappings(opts.selection_mappings))

  local args = search.build_grep_cmd()
  local cmd = table.remove(args, 1)

  local pick_opts = vim.tbl_extend("force", map or {}, {
    search = opts.query,
    source = "grep",
    title = opts.prompt_title,
    cwd = tostring(dir),
    cmd = cmd,
    args = args,
    confirm = function(picker, item, action)
      picker:close()
      if item then
        if opts.callback then
          opts.callback {
            filename = item._path or item.filename,
            col = item.pos and item.pos[2],
            lnum = item.pos and item.pos[1],
            user_data = item.value,
          }
        else
          snacks_picker.actions.jump(picker, item, action)
        end
      end
    end,
  })
  snacks_picker.pick(pick_opts)
end

---@param values string[]|obsidian.PickerEntry[]
---@param opts obsidian.PickerPickOpts|? Options.
M.pick = function(values, opts)
  Picker.state.calling_bufnr = vim.api.nvim_get_current_buf()

  opts = opts or {}
  opts.callback = opts.callback or obsidian.api.open_note

  local preview = vim.iter(values):any(function(value)
    return type(value) == "table" and value.filename ~= nil
  end)

  local entries = {}
  for _, value in ipairs(values) do
    local display
    if type(value) == "string" then
      display = value
      value = { value = value }
    else
      display = opts.format_item and opts.format_item(value) or ut.make_display(value)
    end
    table.insert(entries, {
      text = display,
      file = value.filename,
      value = value.user_data,
      pos = value.lnum and { value.lnum, value.col and value.col - 1 or 0 }, -- from (1, 1) to (1, 0)
      end_pos = value.end_lnum and { value.end_lnum, value.end_col and value.end_col - 1 or 0 },
      dir = value.filename and Path.new(value.filename):is_dir() or false,
    })
  end

  local map = vim.tbl_deep_extend("force", {}, notes_mappings(opts.selection_mappings))

  local pick_opts = vim.tbl_extend("force", map or {}, {
    title = opts.prompt_title,
    items = entries,
    layout = {
      preview = preview,
      preset = "default",
    },
    format = "text",
    confirm = function(picker, item, action)
      picker:close()
      if item then
        if opts.callback then
          if type(item.value) == "function" then
            item.value()
          elseif item.file then
            opts.callback {
              filename = item.file,
              col = item.pos and item.pos[2],
              lnum = item.pos and item.pos[1],
              user_data = item.value,
            }
          else
            opts.callback {
              text = item.text,
              user_data = item.value or item.text,
            }
          end
        else
          snacks_picker.actions.jump(picker, item, action)
        end
      end
    end,
  })

  snacks_picker.pick(pick_opts)
end

return M
