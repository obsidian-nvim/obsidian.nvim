local mini_pick = require "mini.pick"
local obsidian = require "obsidian"
local search = obsidian.search
local Path = obsidian.Path
local Picker = obsidian.Picker
local ut = require "obsidian.picker.util"

---@param entry string
---@return string, integer?, integer?
local function clean_path(entry)
  local parts = vim.split(entry, "\0", { plain = true })
  return parts[1], tonumber(parts[2]), tonumber(parts[3]) - 1
end

local M = {}

---@param opts obsidian.PickerFindOpts|? Options.
M.find_files = function(opts)
  opts = opts or {}
  opts.callback = opts.callback or obsidian.api.open_note

  ---@type obsidian.Path
  local dir = opts.dir and Path.new(opts.dir) or Obsidian.dir

  local path = mini_pick.builtin.cli({
    command = search.build_find_cmd(),
  }, {
    source = {
      name = opts.prompt_title,
      cwd = tostring(dir),
      choose = function(chosen_path)
        -- TODO: use opts.callback
        if not opts.no_default_mappings then
          mini_pick.default_choose(chosen_path)
        end
      end,
    },
  })

  if path and opts.callback then
    opts.callback(tostring(dir / path))
  end
end

---@param opts obsidian.PickerGrepOpts|? Options.
M.grep = function(opts)
  opts = opts and opts or {}

  ---@type obsidian.Path
  local dir = opts.dir and Path.new(opts.dir) or Obsidian.dir

  local pick_opts = {
    source = {
      name = opts.prompt_title,
      cwd = tostring(dir),
      choose = function(path)
        if not opts.no_default_mappings then
          mini_pick.default_choose(path)
        end
      end,
    },
  }

  ---@type string|?
  local result
  if opts.query and string.len(opts.query) > 0 then
    result = mini_pick.builtin.grep({ pattern = opts.query }, pick_opts)
  else
    result = mini_pick.builtin.grep_live({}, pick_opts)
  end

  if result and opts.callback then
    local path, lnum, col = clean_path(result)
    opts.callback {
      filename = tostring(dir / path),
      lnum = lnum,
      col = col,
    }
  end
end

---@param values string[]|obsidian.PickerEntry[]
---@param opts obsidian.PickerPickOpts|? Options.
---@param callback fun(value: obsidian.PickerEntry, ...: obsidian.PickerEntry)|?
M.pick = function(values, opts, callback)
  Picker.state.calling_bufnr = vim.api.nvim_get_current_buf()

  opts = opts and opts or {}
  callback = callback or obsidian.api.open_note

  local entries = {}
  for _, value in ipairs(values) do
    local entry
    if type(value) == "string" then
      entry = {
        user_data = value,
        text = value,
      }
    else
      entry = {
        text = opts.format_item and opts.format_item(value) or ut.make_display(value),
        path = value.filename,
        filename = value.filename,
        lnum = value.lnum,
        col = value.col,
        user_data = value.user_data,
      }
    end
    if value.valid ~= false then
      entries[#entries + 1] = entry
    end
  end

  local entry = mini_pick.start {
    source = {
      name = opts.prompt,
      items = entries,
      choose = function() end,
    },
  }

  if entry then
    callback(entry)
  end
end

return M
