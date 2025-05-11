-- TODO：eventaully move to config

local defualt = {
  actions = {},
  complete = true,
  checkboxs = {
    ---@type "- [ ] " | "* [ ] " | "+ [ ] " | "1. [ ] " | "1) [ ] "
    style = "- [ ] ",
  },
  preview = {
    tag = function(tag_locs, params)
      return ([[Tag used in %d notes]]):format(#tag_locs)
    end,
    note = function(notes, params)
      for i, note in ipairs(notes) do
        if vim.uri_from_fname(note.path.filename) == params.textDocument.uri then
          table.remove(notes, i)
        end
      end
      local note = notes[1]
      return note.path:read()
    end,
  },
  -- option to only show first few links on hover, and completion doc
}

local cmds = require "obsidian.commands"

-- TODO: make context aware
for _, cmd in ipairs(vim.tbl_keys(cmds.commands)) do
  defualt.actions[cmd] = {
    title = cmd,
    command = cmd,
    fn = function()
      vim.cmd.Obsidian(cmd)
    end,
  }
end

return defualt
