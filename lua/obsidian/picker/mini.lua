---@diagnostic disable: unresolved-require
local Picker = require "obsidian.picker"
local Path = require "obsidian.path"
local ut = require "obsidian.picker.util"
local api = require "obsidian.api"

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

--- Register Obsidian workspace entries with MiniPick.registry.
M.setup = function()
  local mini_pick = require "mini.pick"

  mini_pick.registry.obsidian_files = function(call_opts)
    return mini_pick.builtin.files(call_opts, {
      source = { cwd = tostring(api.resolve_workspace_dir()), name = "Obsidian Files" },
    })
  end

  mini_pick.registry.obsidian_grep = function(call_opts)
    return mini_pick.builtin.grep_live(call_opts, {
      source = { cwd = tostring(api.resolve_workspace_dir()), name = "Obsidian Grep" },
    })
  end
end

---@param opts obsidian.PickerGrepOpts Options.
M.grep = function(opts)
  vim.validate("opts", opts, "table")
  local callback = opts.callback or ut.open_notes

  local mini_pick = require "mini.pick"

  ---@type string[]|?
  local selected
  local pick_opts = {
    source = {
      name = opts.prompt_title,
      cwd = tostring(opts.dir),
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
        filename = tostring(Path.new(opts.dir) / path),
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
    entries[#entries + 1] = {
      text = opts.format_item and opts.format_item(value) or ut.make_display(value),
      obsidian_item = value,
    }
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
