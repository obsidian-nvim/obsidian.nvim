-- Useful type definitions go here.

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

---@alias obsidian.agenda.ViewName "day"|"week"|"month"|"year"|"todo"
---@alias obsidian.agenda.ItemStatus "todo"|"done"|string
---@alias obsidian.agenda.Priority "A"|"B"|"C"
---@alias obsidian.agenda.OccurrenceKind "date"|"scheduled"|"due"|"overdue"|"undated"
---@alias obsidian.agenda.SourceDone fun(items: obsidian.agenda.Item[]|nil, err?: string)
---@alias obsidian.agenda.Source fun(ctx: obsidian.agenda.SourceContext, done: obsidian.agenda.SourceDone): obsidian.agenda.Item[]|any

---@class obsidian.agenda.ItemActions
---@field open? fun(item: obsidian.agenda.Item)
---@field toggle? fun(item: obsidian.agenda.Item): boolean|nil

---@class obsidian.agenda.Item
---@field id? string
---@field title? string
---@field status? obsidian.agenda.ItemStatus
---@field checkbox? string
---@field path? string
---@field filename? string
---@field lnum? integer
---@field col? integer
---@field checkbox_col? integer
---@field date? integer
---@field due? integer
---@field scheduled? integer
---@field done? integer
---@field priority? obsidian.agenda.Priority
---@field tags? string[]
---@field raw? string
---@field source? string
---@field metadata? table<string, any>
---@field actions? obsidian.agenda.ItemActions

---@class obsidian.agenda.Occurrence
---@field item obsidian.agenda.Item
---@field date? integer
---@field kind obsidian.agenda.OccurrenceKind

---@class obsidian.agenda.Section
---@field title string
---@field date? integer
---@field items obsidian.agenda.Occurrence[]

---@class obsidian.agenda.ViewRange
---@field from? integer
---@field to? integer

---@class obsidian.agenda.View
---@field name obsidian.agenda.ViewName
---@field title string
---@field range obsidian.agenda.ViewRange
---@field sections obsidian.agenda.Section[]

---@class obsidian.agenda.OpenOpts
---@field view? obsidian.agenda.ViewName
---@field date? integer
---@field bufnr? integer

---@class obsidian.agenda.RendererState : obsidian.agenda.OpenOpts
---@field view_name? obsidian.agenda.ViewName
---@field base_date? integer
---@field request_id? integer
---@field handle? any
---@field line_items? table<integer, obsidian.agenda.Occurrence>

---@class obsidian.agenda.Renderer
---@field loading fun(state: obsidian.agenda.RendererState): integer
---@field render fun(bufnr: integer, view: obsidian.agenda.View, state: obsidian.agenda.RendererState)

---@class obsidian.agenda.ParseOpts
---@field path? string
---@field lnum? integer
---@field source? string

---@class obsidian.agenda.ResolveOpts
---@field default_path? string|obsidian.Path

---@class obsidian.agenda.SourceContext
---@field parse_lines fun(lines: string[], opts?: obsidian.agenda.ParseOpts): obsidian.agenda.Item[]
---@field parse_markdown_file fun(path: string|obsidian.Path, opts?: obsidian.agenda.ParseOpts): obsidian.agenda.Item[]
---@field default_file fun(): obsidian.Path
---@field task { resolve: fun(item: obsidian.agenda.Item, opts?: obsidian.agenda.ResolveOpts): obsidian.agenda.Item }

---@class obsidian.agenda.QuickfixEntry
---@field filename? string
---@field lnum? integer
---@field col? integer
---@field text string
---@field valid? integer
---@field user_data? table<string, any>

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
---@field date? obsidian.config.DateOpts
---@field agenda? obsidian.config.AgendaOpts
---@field completion? obsidian.config.CompletionOpts
---@field picker? obsidian.config.PickerOpts
---@field daily_notes? obsidian.config.DailyNotesOpts
---@field open_notes_in? obsidian.config.OpenStrategy
---@field ui? obsidian.config.UIOpts
---@field attachments? obsidian.config.AttachmentsOpts
---@field callbacks? obsidian.config.CallbackConfig
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
---@field date obsidian.config.DateOpts
---@field agenda obsidian.config.AgendaOpts
---@field completion obsidian.config.CompletionOpts
---@field picker obsidian.config.PickerOpts
---@field daily_notes obsidian.config.DailyNotesOpts
---@field open_notes_in obsidian.config.OpenStrategy
---@field ui obsidian.config.UIOpts
---@field attachments obsidian.config.AttachmentsOpts
---@field callbacks obsidian.config.CallbackConfig
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

---@alias obsidian.config.NewNotesLocation "current_dir" | "notes_subdir"
