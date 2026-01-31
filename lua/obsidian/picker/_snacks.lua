local snacks_picker = require "snacks.picker"

local obsidian = require "obsidian"
local search = obsidian.search
local Picker = obsidian.Picker
local Path = obsidian.Path
local ut = require "obsidian.picker.util"

local M = {}

---@param opts obsidian.PickerFindOpts|? Options.
M.find_files = function(opts)
  opts = opts or {}

  local dir = opts.dir and Path.new(opts.dir) or Obsidian.dir
  local callback = opts.callback or obsidian.api.open_note

  local args = search.build_find_cmd()
  local cmd = table.remove(args, 1)

  local pick_opts = {
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
  }
  snacks_picker.pick(pick_opts)
end

---@param opts obsidian.PickerGrepOpts|? Options.
M.grep = function(opts)
  opts = opts or {}

  local dir = opts.dir and Path.new(opts.dir) or Obsidian.dir
  local callback = opts.callback or obsidian.api.open_note

  local args = search.build_grep_cmd()
  local cmd = table.remove(args, 1)

  local pick_opts = {
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
          col = item.pos and item.pos[2],
          lnum = item.pos and item.pos[1],
          user_data = item.value,
        }
      end
    end,
  }
  snacks_picker.pick(pick_opts)
end

---@param values string[]|obsidian.PickerEntry[]
---@param opts obsidian.PickerPickOpts|? Options.
M.pick = function(values, opts)
  Picker.state.calling_bufnr = vim.api.nvim_get_current_buf()

  opts = opts or {}
  local callback = opts.callback or obsidian.api.open_note

  ---@diagnostic disable-next-line: redundant-parameter
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
    ---@cast value obsidian.PickerEntry
    table.insert(entries, {
      text = display,
      file = value.filename,
      value = value.user_data,
      pos = value.lnum and { value.lnum, value.col and value.col - 1 or 0 }, -- from (1, 1) to (1, 0)
      end_pos = value.end_lnum and { value.end_lnum, value.end_col and value.end_col - 1 or 0 },
      dir = value.filename and Path.new(value.filename):is_dir() or false,
    })
  end

  local pick_opts = {
    title = opts.prompt_title,
    items = entries,
    layout = {
      preview = preview,
      preset = "default",
    },
    format = "text",
    confirm = function(picker, item)
      picker:close()
      if item then
        if item.file then
          callback {
            filename = item.file,
            col = item.pos and item.pos[2],
            lnum = item.pos and item.pos[1],
            text = item.text,
            user_data = item.value,
          }
        else
          callback {
            text = item.text,
            user_data = item.value or item.text,
          }
        end
      end
    end,
  }

  snacks_picker.pick(pick_opts)
end

return M
