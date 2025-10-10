local snacks_picker = require "snacks.picker"

local Path = require "obsidian.path"
local abc = require "obsidian.abc"
local Picker = require "obsidian.pickers.picker"

---@param mapping table
---@return table
local function notes_mappings(mapping)
  if type(mapping) == "table" then
    local opts = { win = { input = { keys = {} } }, actions = {} }
    for k, v in pairs(mapping) do
      local name = string.gsub(v.desc, " ", "_")
      opts.win.input.keys = {
        [k] = { name, mode = { "n", "i" }, desc = v.desc },
      }
      opts.actions[name] = function(picker, item)
        picker:close()
        vim.schedule(function()
          v.callback(item.value or item._path)
        end)
      end
    end
    return opts
  end
  return {}
end

---@class obsidian.pickers.SnacksPicker : obsidian.Picker
local SnacksPicker = abc.new_class({
  __tostring = function()
    return "SnacksPicker()"
  end,
}, Picker)

---@param opts obsidian.PickerFindOpts|? Options.
SnacksPicker.find_files = function(self, opts)
  opts = opts or {}

  ---@type obsidian.Path
  local dir = opts.dir.filename and Path.new(opts.dir.filename) or Obsidian.dir

  local map = vim.tbl_deep_extend("force", {}, notes_mappings(opts.selection_mappings))

  local args = self:_build_find_cmd()
  local cmd = table.remove(args, 1)

  local pick_opts = vim.tbl_extend("force", map or {}, {
    pattern = opts.query,
    source = "files",
    title = opts.prompt_title,
    cwd = tostring(dir),
    cmd = cmd,
    args = args,
    confirm = function(picker, item, action)
      picker:close()
      if item then
        if opts.callback then
          opts.callback(item._path)
        else
          snacks_picker.actions.jump(picker, item, action)
        end
      end
    end,
  })
  snacks_picker.pick(pick_opts)
end

---@param opts obsidian.PickerGrepOpts|? Options.
SnacksPicker.grep = function(self, opts)
  opts = opts or {}

  ---@type obsidian.Path
  local dir = opts.dir.filename and Path.new(opts.dir.filename) or Obsidian.dir

  local map = vim.tbl_deep_extend("force", {}, notes_mappings(opts.selection_mappings))

  local args = self:_build_grep_cmd()
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
            value = item.value,
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
SnacksPicker.pick = function(self, values, opts)
  self.calling_bufnr = vim.api.nvim_get_current_buf()

  opts = opts or {}

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
      display = opts.format_item and opts.format_item(value) or self:_make_display(value)
    end
    table.insert(entries, {
      text = display,
      file = value.filename,
      value = value.value,
      pos = value.lnum and { value.lnum, value.col or 0 },
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
          if item.file then
            opts.callback {
              filename = item.file,
              col = item.pos and item.pos[2],
              lnum = item.pos and item.pos[1],
              value = item.value,
            }
          else
            opts.callback {
              value = item.value,
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

return SnacksPicker
