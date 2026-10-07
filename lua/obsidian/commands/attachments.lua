local picker = require "obsidian.picker"
local filetypes = require "obsidian.filetypes"
local log = require "obsidian.log"
local picker_util = require "obsidian.picker.util"
local search = require "obsidian.search"
local api = require "obsidian.api"
local Path = require "obsidian.path"

---@class obsidian.PickerAttachmentOpts
---
---@field query string|?
---@field selection_mappings obsidian.PickerMappingTable|?

--- Find attachments in a directory and open selected files externally by default.
---
---@param query string|?
local find_attachments = function(query)
  local dir = api.resolve_workspace_dir()
  query = query and vim.trim(query):lower() or nil
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
    }
  end, function(code)
    if code ~= 0 then
      log.err("Failed to enumerate attachments in '%s'", dir)
      return
    end

    picker.select(entries, {
      prompt = "Attachments",
      allow_multiple = true,
      -- selection_mappings = {}, TODO: picker management keymap actions
      format_item = picker_util.make_display,
    }, function(items)
      for _, item in ipairs(items) do
        vim.ui.open(item.filename)
      end
    end)
  end)
end

---@param data obsidian.CommandArgs
return function(data)
  find_attachments(data.args ~= "" and data.args or nil)
end
