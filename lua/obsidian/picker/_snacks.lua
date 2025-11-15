local snacks_picker = require "snacks.picker"

local obsidian = require "obsidian"
local search = obsidian.search
local Path = obsidian.Path

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
          v.callback(item.user_data or item._path)
        end)
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
            value = item.user_data,
          }
        else
          snacks_picker.actions.jump(picker, item, action)
        end
      end
    end,
  })
  snacks_picker.pick(pick_opts)
end

return M
