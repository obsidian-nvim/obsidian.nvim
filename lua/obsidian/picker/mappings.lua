local M = {}

M.new_note = function(query)
  if not query or vim.trim(query) == "" then
    return
  end
  ---@diagnostic disable-next-line: missing-fields
  require "obsidian.commands.new" { args = query }
end

return M
