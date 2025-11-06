---@type obsidian.config.Internal
return {
  -- TODO: remove these in 4.0.0
  legacy_commands = true,
  note_frontmatter_func = require("obsidian.builtin").frontmatter,
  disable_frontmatter = false,
  ---@class obsidian.config.StatuslineOpts
  ---
  ---@field format? string
  ---@field enabled? boolean
  statusline = {
    format = "{{backlinks}} backlinks  {{properties}} properties  {{words}} words  {{chars}} chars",
    enabled = true,
  },

  -- TODO:: replace with more general options before 4.0.0
  follow_url_func = vim.ui.open,
  follow_img_func = vim.ui.open,
  notes_subdir = nil,
  new_notes_location = "current_dir",

  workspaces = {},
  log_level = vim.log.levels.INFO,
  note_id_func = require("obsidian.builtin").zettel_id,
  note_path_func = function(spec)
    local path = spec.dir / tostring(spec.id)
    return path
  end,
  wiki_link_func = require("obsidian.builtin").wiki_link_id_prefix,
  markdown_link_func = require("obsidian.builtin").markdown_link,
  preferred_link_style = "wiki",
  open_notes_in = "current",

  ---@class obsidian.config.NoteOpts
  ---
  ---Default template to use, relative to template.folder or an absolute path.
  ---The default looks like:
  ---
  ---```markdown
  ------
  ---id: {{id}}
  ---aliases: []
  ---tags: []
  ------
  ---```
  ---
  ---@field template string|?
  note = {
    template = (function()
      local root = vim.iter(vim.api.nvim_list_runtime_paths()):find(function(path)
        return vim.endswith(path, "obsidian.nvim")
      end)
      if not root then
        return nil
      end
      return vim.fs.joinpath(root, "data/default_template.md")
    end)(),
  },

  ---@class obsidian.config.FrontmatterOpts
  ---
  --- Whether to enable frontmatter, boolean for global on/off, or a function that takes filename and returns boolean.
  ---@field enabled? (fun(fname: string?): boolean)|boolean
  ---
  --- Function to turn Note attributes into frontmatter.
  ---@field func? fun(note: obsidian.Note): table<string, any>
  --- Function that is passed to table.sort to sort the properties, or a fixed order of properties.
  ---
  --- List of string that sorts frontmatter properties, or a function that compares two values, set to vim.NIL/false to do no sorting
  ---@field sort? string[] | (fun(a: any, b: any): boolean) | vim.NIL | boolean
  frontmatter = {
    enabled = true,
    func = require("obsidian.builtin").frontmatter,
    sort = { "id", "aliases", "tags" },
  },

  ---@class obsidian.config.TemplateOpts
  ---
  ---@field folder string|obsidian.Path|?
  ---@field date_format string|?
  ---@field time_format string|?
  --- A map for custom variables, the key should be the variable and the value a function.
  --- Functions are called with obsidian.TemplateContext objects as their sole parameter.
  --- See: https://github.com/obsidian-nvim/obsidian.nvim/wiki/Template#substitutions
  ---@field substitutions table<string, (fun(ctx: obsidian.TemplateContext):string)|(fun(): string)|string>|?
  ---@field customizations table<string, obsidian.config.CustomTemplateOpts>|?
  templates = {
    folder = nil,
    date_format = nil,
    time_format = nil,
    substitutions = {},

    ---@class obsidian.config.CustomTemplateOpts
    ---
    ---@field notes_subdir? string
    ---@field note_id_func? (fun(title: string|?, path: obsidian.Path|?): string)
    customizations = {},
  },

  ---@class obsidian.config.BacklinkOpts
  ---
  ---@field parse_headers boolean
  backlinks = {
    parse_headers = true,
  },

  ---@class obsidian.config.CompletionOpts
  ---
  ---@field min_chars? integer
  ---@field match_case? boolean
  ---@field create_new? boolean
  completion = {
    min_chars = 2,
    match_case = true,
    create_new = true,
  },

  ---@class obsidian.config.PickerNoteMappingOpts
  ---
  ---@field new? string
  ---@field insert_link? string

  ---@class obsidian.config.PickerTagMappingOpts
  ---
  ---@field tag_note? string
  ---@field insert_tag? string

  ---@class obsidian.config.PickerOpts
  ---
  ---@field name obsidian.config.Picker|?
  ---@field note_mappings? obsidian.config.PickerNoteMappingOpts
  ---@field tag_mappings? obsidian.config.PickerTagMappingOpts
  picker = {
    name = nil,
    note_mappings = {
      new = "<C-x>",
      insert_link = "<C-l>",
    },
    tag_mappings = {
      tag_note = "<C-x>",
      insert_tag = "<C-l>",
    },
  },

  ---@class obsidian.config.SearchOpts
  ---
  ---@field sort_by string
  ---@field sort_reversed boolean
  ---@field max_lines integer
  search = {
    sort_by = "modified",
    sort_reversed = true,
    max_lines = 1000,
  },

  ---@class obsidian.config.DailyNotesOpts
  ---
  ---@field folder? string
  ---@field date_format? string
  ---@field alias_format? string
  ---@field template? string
  ---@field default_tags? string[]
  ---@field workdays_only? boolean
  daily_notes = {
    folder = nil,
    date_format = "%Y-%m-%d",
    alias_format = nil,
    default_tags = { "daily-notes" },
    workdays_only = true,
  },

  ---@class obsidian.config.UICharSpec
  ---@field char string
  ---@field hl_group string

  ---@class obsidian.config.CheckboxSpec : obsidian.config.UICharSpec
  ---@field char string
  ---@field hl_group string

  ---@class obsidian.config.UIStyleSpec
  ---@field hl_group string

  ---@class obsidian.config.UIOpts
  ---
  ---@field enable boolean
  ---@field ignore_conceal_warn boolean
  ---@field update_debounce integer
  ---@field max_file_length integer|?
  ---@field checkboxes table<string, obsidian.config.CheckboxSpec>
  ---@field bullets obsidian.config.UICharSpec|?
  ---@field external_link_icon obsidian.config.UICharSpec
  ---@field reference_text obsidian.config.UIStyleSpec
  ---@field highlight_text obsidian.config.UIStyleSpec
  ---@field tags obsidian.config.UIStyleSpec
  ---@field block_ids obsidian.config.UIStyleSpec
  ---@field hl_groups table<string, table>
  ui = {
    enable = true,
    ignore_conceal_warn = false,
    update_debounce = 200,
    max_file_length = 5000,
    checkboxes = {
      [" "] = { char = "󰄱", hl_group = "obsidiantodo" },
      ["~"] = { char = "󰰱", hl_group = "obsidiantilde" },
      ["!"] = { char = "", hl_group = "obsidianimportant" },
      [">"] = { char = "", hl_group = "obsidianrightarrow" },
      ["x"] = { char = "", hl_group = "obsidiandone" },
    },
    bullets = { char = "•", hl_group = "ObsidianBullet" },
    external_link_icon = { char = "", hl_group = "ObsidianExtLinkIcon" },
    reference_text = { hl_group = "ObsidianRefText" },
    highlight_text = { hl_group = "ObsidianHighlightText" },
    tags = { hl_group = "ObsidianTag" },
    block_ids = { hl_group = "ObsidianBlockID" },
    hl_groups = {
      ObsidianTodo = { bold = true, fg = "#f78c6c" },
      ObsidianDone = { bold = true, fg = "#89ddff" },
      ObsidianRightArrow = { bold = true, fg = "#f78c6c" },
      ObsidianTilde = { bold = true, fg = "#ff5370" },
      ObsidianImportant = { bold = true, fg = "#d73128" },
      ObsidianBullet = { bold = true, fg = "#89ddff" },
      ObsidianRefText = { underline = true, fg = "#c792ea" },
      ObsidianExtLinkIcon = { fg = "#c792ea" },
      ObsidianTag = { italic = true, fg = "#89ddff" },
      ObsidianBlockID = { italic = true, fg = "#89ddff" },
      ObsidianHighlightText = { bg = "#75662e" },
    },
  },

  ---@class obsidian.config.AttachmentsOpts
  ---
  ---Default folder to save images to, relative to the vault root (/) or current dir (.), see https://github.com/obsidian-nvim/obsidian.nvim/wiki/Images#change-image-save-location
  ---@field folder? string
  ---
  ---Default name for pasted images
  ---@field img_name_func? fun(): string
  ---
  ---Default text to insert for pasted images
  ---@field img_text_func? fun(path: obsidian.Path): string
  ---
  ---Whether to confirm the paste or not. Defaults to true.
  ---@field confirm_img_paste? boolean
  attachments = {
    folder = "attachments",
    img_text_func = require("obsidian.builtin").img_text_func,
    img_name_func = function()
      return string.format("Pasted image %s", os.date "%Y%m%d%H%M%S")
    end,
    confirm_img_paste = true, -- TODO: move to paste module, paste.confirm
  },

  ---@class obsidian.config.CallbackConfig
  ---
  ---Runs right after setup
  ---@field post_setup? fun()
  ---
  ---Runs when entering a note buffer.
  ---@field enter_note? fun(note: obsidian.Note)
  ---
  ---Runs when leaving a note buffer.
  ---@field leave_note? fun(note: obsidian.Note)
  ---
  ---Runs right before writing a note buffer.
  ---@field pre_write_note? fun(note: obsidian.Note)
  ---
  ---Runs anytime the workspace is set/changed.
  ---@field post_set_workspace? fun(workspace: obsidian.Workspace)
  callbacks = {},

  ---@class obsidian.config.FooterOpts
  ---
  ---@field enabled? boolean
  ---@field format? string
  ---@field hl_group? string
  ---@field separator? string|false Set false to disable separator; set an empty string to insert a blank line separator.
  footer = {
    enabled = true,
    format = "{{backlinks}} backlinks  {{properties}} properties  {{words}} words  {{chars}} chars",
    hl_group = "Comment",
    separator = string.rep("-", 80),
  },

  ---@class obsidian.config.OpenOpts
  ---
  ---Opens the file with current line number
  ---@field use_advanced_uri? boolean
  ---
  ---Function to do the opening, default to vim.ui.open
  ---@field func? fun(uri: string)
  ---
  ---URI scheme whitelist, new values are appended to this list, and URIs with schemes in this list, will not be prompted to confirm opening
  ---@field schemes? string[]
  open = {
    use_advanced_uri = false,
    func = vim.ui.open,
    schemes = { "https", "http", "file", "mailto" },
  },

  ---@class obsidian.config.CheckboxOpts
  ---
  ---@field enabled? boolean
  ---
  ---Order of checkbox state chars, e.g. { " ", "x" }
  ---@field order? string[]
  ---
  ---Whether to create new checkbox on paragraphs
  ---@field create_new? boolean
  checkbox = {
    enabled = true,
    create_new = true,
    order = { " ", "~", "!", ">", "x" },
  },

  ---@class obsidian.config.CommentOpts
  ---@field enabled boolean
  comment = {
    enabled = false,
  },
}
