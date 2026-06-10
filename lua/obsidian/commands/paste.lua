local log = require "obsidian.log"

local kinds = { "auto", "html", "url", "text" }

---@param data obsidian.CommandArgs
return function(data)
  ---@type obsidian.api.PasteOpts
  local opts = {}

  local arg = vim.trim(data.args or "")
  if arg ~= "" then
    if not vim.list_contains(kinds, arg) then
      return log.err("Invalid paste kind '%s', expected one of: %s", arg, table.concat(kinds, ", "))
    end
    opts.kind = arg
  end

  require("obsidian.actions").paste(opts)
end
