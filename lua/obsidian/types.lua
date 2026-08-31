-- Useful type definitions and runtime enums go here.

local M = {}

---@enum obsidian.config.OpenStrategy
M.OpenStrategy = {
  current = "current",
  vsplit = "vsplit",
  hsplit = "hsplit",
  vsplit_force = "vsplit_force",
  hsplit_force = "hsplit_force",
}

---@enum obsidian.config.SortBy
M.SortBy = {
  path = "path",
  modified = "modified",
  accessed = "accessed",
  created = "created",
}

---@enum obsidian.config.Picker
M.Picker = {
  telescope = "telescope.nvim",
  fzf_lua = "fzf-lua",
  mini = "mini.pick",
  snacks = "snacks.picker",
}

---@enum obsidian.config.NewNotesLocation
M.NewNotesLocation = {
  current_dir = "current_dir",
  notes_subdir = "notes_subdir",
}

---@enum obsidian.link.LinkStyle
M.LinkStyle = {
  wiki = "wiki",
  markdown = "markdown",
}

---@alias obsidian.link.LinkStyleOption obsidian.link.LinkStyle|fun(opts: obsidian.link.LinkCreationOpts): string

---@enum obsidian.link.LinkFormat
M.LinkFormat = {
  shortest = "shortest",
  relative = "relative",
  absolute = "absolute",
}

---@enum obsidian.config.SyncTrigger
M.SyncTrigger = {
  continuous = "continuous",
  on_write = "on_write",
  manual = "manual",
}

---@enum obsidian.config.SyncMode
M.SyncMode = {
  bidirectional = "bidirectional",
  pull_only = "pull-only",
  mirror_remote = "mirror-remote",
}

---@enum obsidian.config.ConflictStrategy
M.ConflictStrategy = {
  merge = "merge",
  conflict = "conflict",
}

---@enum obsidian.sync.FileType
M.SyncFileType = {
  image = "image",
  audio = "audio",
  video = "video",
  pdf = "pdf",
  unsupported = "unsupported",
}

---@enum obsidian.sync.ConfigCategory
M.SyncConfigCategory = {
  app = "app",
  appearance = "appearance",
  appearance_data = "appearance-data",
  hotkey = "hotkey",
  core_plugin = "core-plugin",
  core_plugin_data = "core-plugin-data",
  community_plugin = "community-plugin",
  community_plugin_data = "community-plugin-data",
}

---@alias obsidian.CommandArgs vim.api.keyset.create_user_command.command_args

---@class obsidian.InsertTemplateContext
---The table passed to user substitution functions when inserting templates into a buffer.
---
---@field type "insert_template"
---@field template_name string|obsidian.Path The name or path of the template being used.
---@field templates_dir obsidian.Path|? The folder containing the template file.
---@field location [integer, integer, integer, integer] `{ buf, win, row, col }` location from which the request was made.
---@field partial_note? obsidian.Note An optional note with fields to copy from.

---@class obsidian.CloneTemplateContext
---The table passed to user substitution functions when cloning template files to create new notes.
---
---@field type "clone_template"
---@field template_name string|obsidian.Path The name or path of the template being used.
---@field templates_dir obsidian.Path|? The folder containing the template file.
---@field destination_path obsidian.Path The path the cloned template will be written to.
---@field partial_note obsidian.Note The note being written.

---@alias obsidian.TemplateContext obsidian.InsertTemplateContext | obsidian.CloneTemplateContext
---The table passed to user substitution functions. Use `ctx.type` to distinguish between the different kinds.

---@class obsidian.config
---@field workspaces obsidian.workspace.WorkspaceSpec[]
---@field log_level? integer
---@field notes_subdir? string
---@field file? obsidian.config.FileOpts
---@field templates? obsidian.config.TemplateOpts
---@field new_notes_location? obsidian.config.NewNotesLocation
---@field note_id_func? (fun(title: string|?, path: obsidian.Path|?): string)|?
---@field note_path_func? fun(spec: { id: string, dir: obsidian.Path, title: string|? }): string|obsidian.Path
---@field frontmatter? obsidian.config.FrontmatterOpts
---@field backlinks? obsidian.config.BacklinkOpts
---@field completion? obsidian.config.CompletionOpts
---@field picker? obsidian.config.PickerOpts
---@field daily_notes? obsidian.config.DailyNotesOpts
---@field open_notes_in? obsidian.config.OpenStrategy
---@field ui? obsidian.config.UIOpts
---@field attachments? obsidian.config.AttachmentsOpts
---@field callbacks? obsidian.config.CallbackConfig
---@field resolvers? obsidian.config.ResolverConfig
---@field legacy_commands? boolean
---@field statusline? obsidian.config.StatuslineOpts
---@field footer? obsidian.config.FooterOpts
---@field open? obsidian.config.OpenOpts
---@field checkbox? obsidian.config.CheckboxOpts
---@field comment? obsidian.config.CommentOpts
---@field search? obsidian.config.SearchOpts
---@field note? obsidian.config.NoteOpts
---@field link? obsidian.config.LinkOpts
---@field unique_note? obsidian.config.UniqueNoteOpts
---@field sync? obsidian.config.SyncOpts
---@field slides? obsidian.config.SlidesOpts
---@field cache? obsidian.config.CacheOpts

---@class obsidian.config.Internal
---@field workspaces obsidian.workspace.WorkspaceSpec[]
---@field log_level integer
---@field notes_subdir string|?
---@field file obsidian.config.FileOpts
---@field templates obsidian.config.TemplateOpts
---@field new_notes_location obsidian.config.NewNotesLocation
---@field note_id_func (fun(id: string|?, path: obsidian.Path|?): string)
---@field note_path_func (fun(spec: { id: string, dir: obsidian.Path }): string|obsidian.Path)
---@field frontmatter obsidian.config.FrontmatterOpts
---@field backlinks obsidian.config.BacklinkOpts
---@field completion obsidian.config.CompletionOpts
---@field picker obsidian.config.PickerOpts
---@field daily_notes obsidian.config.DailyNotesOpts
---@field open_notes_in obsidian.config.OpenStrategy
---@field ui obsidian.config.UIOpts
---@field attachments obsidian.config.AttachmentsOpts
---@field callbacks obsidian.config.CallbackConfig
---@field resolvers obsidian.config.ResolverConfig
---@field legacy_commands boolean
---@field statusline obsidian.config.StatuslineOpts
---@field footer obsidian.config.FooterOpts
---@field open obsidian.config.OpenOpts
---@field checkbox obsidian.config.CheckboxOpts
---@field comment obsidian.config.CommentOpts
---@field search obsidian.config.SearchOpts
---@field note obsidian.config.NoteOpts
---@field link obsidian.config.LinkOpts
---@field unique_note obsidian.config.UniqueNoteOpts
---@field sync obsidian.config.SyncOpts
---@field slides obsidian.config.SlidesOpts
---@field cache obsidian.config.CacheOpts

return M
