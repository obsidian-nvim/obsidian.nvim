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

local build_selection_mappings = function(mappings)
  local actions = {}
  for key, mapping in pairs(mappings) do
    actions[mapping.desc:gsub(" ", "_")] = {
      char = key,
      func = function(...)
        _ = ...
        -- mapping.callback({ filename = path })
      end,
    }
  end
  return actions
end

---@param opts obsidian.PickerFindOpts|? Options.
M.find_files = function(opts)
  opts = opts or {}
  opts.callback = opts.callback or obsidian.api.open_note

  ---@type obsidian.Path
  local dir = opts.dir and Path.new(opts.dir) or Obsidian.dir

  local mappings

  if not opts.no_default_mappings then
    mappings = build_selection_mappings(opts.selection_mappings)
  end

  local path = mini_pick.builtin.cli({
    command = search.build_find_cmd(),
    mappings = mappings,
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
M.pick = function(values, opts)
  Picker.state.calling_bufnr = vim.api.nvim_get_current_buf()

  opts = opts and opts or {}
  opts.callback = opts.callback or obsidian.api.open_note

  local entries = {}
  for _, value in ipairs(values) do
    if type(value) == "string" then
      value = {
        user_data = value,
        text = value,
      }
    else
      value.text = opts.format_item and opts.format_item(value) or ut.make_display(value)
      ---@diagnostic disable-next-line: inject-field
      value.path = value.filename -- HACK:
    end
    if value.valid ~= false then
      entries[#entries + 1] = value
    end
  end

  local entry = mini_pick.start {
    source = {
      name = opts.prompt_title,
      items = entries,
      choose = function() end,
    },
  }

  if entry and opts.callback then
    opts.callback(entry)
  end
end

return M
