local picker = require "obsidian.picker"
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

  search.find_attachments_async(query, function(paths, err)
    if err then
      log.err(err)
      return
    end

    picker.select(paths, {
      prompt = "Attachments",
      allow_multiple = true,
      query = query,
      format_item = function(path)
        return tostring(Path.new(path):relative_to(dir))
      end,
      -- TODO: picker management keymap actions in selection mappings
      -- TODO: preview_item once obsidian image lands
    }, function(selections)
      for _, path in ipairs(selections) do
        vim.ui.open(path)
      end
    end)
  end, {
    dir = dir,
    sort_by = Obsidian.opts.search.sort_by,
    sort_reversed = Obsidian.opts.search.sort_reversed,
  })
end

---@param data obsidian.CommandArgs
return function(data)
  find_attachments(data.args ~= "" and data.args or nil)
end
