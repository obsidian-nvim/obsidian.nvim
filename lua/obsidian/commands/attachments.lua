local picker = require "obsidian.picker"
local filetypes = require "obsidian.filetypes"
local log = require "obsidian.log"
local picker_util = require "obsidian.picker.util"
local search = require "obsidian.search"
local api = require "obsidian.api"
local Path = require "obsidian.path"

---@class obsidian.PickerAttachmentOpts
---
---@field prompt_title string|?
---@field dir string|obsidian.Path|?
---@field query string|?
---@field callback fun(paths: string[])|?
---@field selection_mappings obsidian.PickerMappingTable|?

-- TODO: picker management keymap actions
--- Find attachments in a directory and open selected files externally by default.
---
---@param opts obsidian.PickerAttachmentOpts|?
local find_attachments = function(opts)
  opts = opts or {}

  local dir = Path.new(opts.dir or api.resolve_workspace_dir()):resolve { strict = true }
  local query = opts.query and vim.trim(opts.query):lower() or nil
  if query == "" then
    query = nil
  end

  local entries = {}
  return search.find_async(dir, nil, {
    sort_by = Obsidian.opts.search.sort_by,
    sort_reversed = Obsidian.opts.search.sort_reversed,
    include_non_markdown = true,
  }, function(path)
    if not filetypes.is_attachment(path) then
      return
    end

    local rel_path = tostring(Path.new(path):relative_to(dir))
    if query and not rel_path:lower():find(query, 1, true) then
      return
    end

    entries[#entries + 1] = {
      filename = path,
      text = rel_path,
      user_data = { attachment = true },
    }
  end, function(code)
    if code ~= 0 then
      log.err("Failed to enumerate attachments in '%s'", dir)
      return
    end

    picker.select(entries, {
      prompt = opts.prompt_title or "Attachments",
      allow_multiple = true,
      selection_mappings = opts.selection_mappings,
      -- The initial query is applied above so it also matches directories.
      query = nil,
      format_item = picker_util.make_display,
      preview_item = function(entry)
        return picker_util.preview_path(entry.filename)
      end,
    }, function(items)
      local paths = vim.tbl_map(function(item)
        return item.filename
      end, items or {})
      if opts.callback then
        opts.callback(paths)
      else
        for _, path in ipairs(paths) do
          vim.ui.open(path)
        end
      end
    end)
  end)
end

---@param data obsidian.CommandArgs
return function(data)
  find_attachments {
    prompt_title = "Attachments",
    query = data.args ~= "" and data.args or nil,
  }
end
