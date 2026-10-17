-- Copy this file to .nvim.lua in the vault root and enable Neovim's 'exrc'.
local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fs.dirname(vim.fs.normalize(source))

require("obsidian").setup {
  legacy_commands = false,
  workspaces = {
    { name = vim.fs.basename(root), path = root, strict = true },
  },
  notes_subdir = "Notes",
  new_notes_location = "notes_subdir",
  note_id_func = function(title)
    return title or os.date "%d-%m-%Y-%H-%M"
  end,
  daily_notes = {
    folder = "Inbox",
    date_format = "DD-MM-YYYY",
  },
  templates = {
    folder = "Templates",
    date_format = "DD-MM-YYYY",
    time_format = "HH:mm",
    customizations = {
      ["daily-plan"] = {
        notes_subdir = "Personal/Schedule Daily",
        -- This rule always uses the date, even when a title is supplied.
        note_id_func = function()
          return "SD - " .. os.date "%d-%m-%Y"
        end,
      },
    },
  },
  attachments = {
    folder = "Attachments/Images",
  },
  frontmatter = {
    enabled = false,
  },
}
