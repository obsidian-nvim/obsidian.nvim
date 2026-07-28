---@diagnostic disable: unresolved-require
local search = require "obsidian.search"
local Path = require "obsidian.path"
local Picker = require "obsidian.picker"
local ut = require "obsidian.picker.util"

---@param entry string
---@return string, integer?, integer?
local function clean_path(entry)
  local parts = vim.split(entry, "\0", { plain = true })
  local path = parts[1] or ""
  local lnum = tonumber(parts[2])
  local col = tonumber(parts[3])
  ---@cast lnum integer?
  ---@cast col integer?
  return path, lnum, col
end

local M = {}

local build_selection_mappings = function(mappings)
  local actions = {}
  for key, mapping in pairs(mappings) do
    actions[mapping.desc:gsub(" ", "_")] = {
      char = key,
      func = function()
        -- mapping.callback({ filename = path })
      end,
    }
  end
  return actions
end

---@param opts obsidian.PickerFindOpts|? Options.
M.find_files = function(opts)
  opts = opts or {}
  local callback = opts.callback or ut.open_notes

  local mini_pick = require "mini.pick"

  ---@type obsidian.Path
  local dir = opts.dir and Path.new(opts.dir) or Obsidian.dir

  local mappings

  if not opts.no_default_mappings then
    mappings = build_selection_mappings(opts.selection_mappings)
  end

  local selected
  local path = mini_pick.builtin.cli({
    command = search.build_find_cmd(nil, nil, { include_non_markdown = opts.include_non_markdown }),
    mappings = mappings,
  }, {
    source = {
      name = opts.prompt_title,
      cwd = tostring(dir),
      choose = function(chosen_path)
        selected = { chosen_path }
      end,
      choose_marked = function(chosen_paths)
        selected = chosen_paths
      end,
    },
  })

  selected = selected or (path and { path }) or {}
  if #selected > 0 then
    callback(vim.tbl_map(function(chosen_path)
      return tostring(dir / chosen_path)
    end, selected))
  end
end

---@param opts obsidian.PickerGrepOpts|? Options.
M.grep = function(opts)
  opts = opts and opts or {}
  local callback = opts.callback or ut.open_notes

  local mini_pick = require "mini.pick"

  ---@type obsidian.Path
  local dir = opts.dir and Path.new(opts.dir) or Obsidian.dir

  ---@type string[]|?
  local selected
  local pick_opts = {
    source = {
      name = opts.prompt_title,
      cwd = tostring(dir),
      choose = function(item)
        selected = { item }
      end,
      choose_marked = function(items)
        selected = items
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

  selected = selected or (result and { result }) or {}
  if #selected > 0 then
    callback(vim.tbl_map(function(item)
      local path, lnum, col = clean_path(item)
      return {
        filename = tostring(dir / path),
        lnum = lnum,
        col = col,
      }
    end, selected))
  end
end

---@param values any[]
---@param opts obsidian.PickerSelectOpts|? Options.
---@param on_choice fun(choices: any[])|?
M.select = function(values, opts, on_choice)
  Picker.state.calling_bufnr = vim.api.nvim_get_current_buf()

  opts = opts and opts or {}
  on_choice = on_choice or function() end

  local mini_pick = require "mini.pick"

  local entries = {}
  for _, value in ipairs(values) do
    local entry
    if type(value) == "string" then
      entry = {
        text = value,
        obsidian_item = value,
      }
    else
      entry = vim.tbl_extend("force", {}, value, {
        text = opts.format_item and opts.format_item(value) or ut.make_display(value),
        path = value.filename, -- HACK:
        obsidian_item = value,
      })
    end
    if type(value) ~= "table" or value.valid ~= false then
      entries[#entries + 1] = entry
    end
  end

  local source = {
    name = opts.prompt,
    items = entries,
    choose = function() end,
  }

  local marked_entries
  if opts.allow_multiple then
    source.choose_marked = function(items)
      marked_entries = items
    end
  end

  if opts.preview_item then
    source.preview = function(buf_id, item)
      local winid = vim.fn.bufwinid(buf_id)
      if winid ~= -1 then
        ut.show_preview_spec(winid, opts.preview_item(item.obsidian_item or item))
      end
    end
  end

  local entry = mini_pick.start {
    source = source,
  }

  local selected = marked_entries or (entry and { entry }) or {}
  on_choice(vim.tbl_map(function(item)
    return item.obsidian_item or item
  end, selected))
end

return M
