local picker = require "obsidian.picker"
local filetypes = require "obsidian.filetypes"
local log = require "obsidian.log"
local search = require "obsidian.search"
local api = require "obsidian.api"
local Path = require "obsidian.path"

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
    entries[#entries + 1] = path
  end, function(code)
    if code ~= 0 then
      log.err("Failed to enumerate attachments in '%s'", dir)
      return
    end

    picker.select(entries, {
      prompt = "Attachments",
      allow_multiple = true,
      query = query,
      format_item = function(path)
        return tostring(Path.new(path):relative_to(dir))
      end,
      -- TODO: picker management keymap actions in selection mappings
      -- TODO: preview_item
    }, function(paths)
      for _, path in ipairs(paths) do
        vim.ui.open(path)
      end
    end)
  end)
end

---@param data obsidian.CommandArgs
return function(data)
  find_attachments(data.args ~= "" and data.args or nil)
end
