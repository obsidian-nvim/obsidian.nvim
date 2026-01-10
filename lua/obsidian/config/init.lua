---@diagnostic disable: inject-field
local log = require "obsidian.log"

local config = {}

---@enum obsidian.config.OpenStrategy
config.OpenStrategy = {
  current = "current",
  vsplit = "vsplit",
  hsplit = "hsplit",
  vsplit_force = "vsplit_force",
  hsplit_force = "hsplit_force",
}

---@enum obsidian.config.SortBy
config.SortBy = {
  path = "path",
  modified = "modified",
  accessed = "accessed",
  created = "created",
}

---@alias obsidian.config.NewNotesLocation "current_dir" | "notes_subdir"

---@enum obsidian.config.LinkStyle
config.LinkStyle = {
  wiki = "wiki",
  markdown = "markdown",
}

---@enum obsidian.config.Picker
config.Picker = {
  telescope = "telescope.nvim",
  fzf_lua = "fzf-lua",
  mini = "mini.pick",
  snacks = "snacks.pick",
}

config.default = require "obsidian.config.default"

local tbl_override = function(defaults, overrides)
  local out = vim.tbl_extend("force", defaults, overrides)
  for k, v in pairs(out) do
    if v == vim.NIL then
      out[k] = nil
    end
  end
  return out
end

local function deprecate(name, alternative, version)
  vim.deprecate(name, alternative, version, "obsidian.nvim", false)
end

--- Normalize options.
---
---@param opts obsidian.config
---@param defaults obsidian.config.Internal|?
---
---@return obsidian.config.Internal
config.normalize = function(opts, defaults)
  local builtin = require "obsidian.builtin"
  local util = require "obsidian.util"

  opts = opts or {}

  if not defaults then
    defaults = config.default
  end

  -------------------------------------------------------------------------------------
  -- Rename old fields for backwards compatibility and warn about deprecated fields. --
  -------------------------------------------------------------------------------------

  if opts.ui and opts.ui.tick then
    opts.ui.update_debounce = opts.ui.tick
    opts.ui.tick = nil
  end

  if not opts.picker then
    opts.picker = {}
    if opts.finder then
      opts.picker.name = opts.finder
      opts.finder = nil
    end
    if opts.finder_mappings then
      opts.picker.note_mappings = opts.finder_mappings
      opts.finder_mappings = nil
    end
    if opts.picker.mappings and not opts.picker.note_mappings then
      opts.picker.note_mappings = opts.picker.mappings
      opts.picker.mappings = nil
    end
  end

  if opts.wiki_link_func == nil and opts.completion ~= nil then
    local warn = false

    if opts.completion.prepend_note_id then
      opts.wiki_link_func = builtin.wiki_link_id_prefix
      opts.completion.prepend_note_id = nil
      warn = true
    elseif opts.completion.prepend_note_path then
      opts.wiki_link_func = builtin.wiki_link_path_prefix
      opts.completion.prepend_note_path = nil
      warn = true
    elseif opts.completion.use_path_only then
      opts.wiki_link_func = builtin.wiki_link_path_only
      opts.completion.use_path_only = nil
      warn = true
    end

    if warn then
      log.warn_once(
        "The config options 'completion.prepend_note_id', 'completion.prepend_note_path', and 'completion.use_path_only' "
          .. "are deprecated. Please use 'wiki_link_func' instead.\n"
          .. "See https://github.com/epwalsh/obsidian.nvim/pull/406"
      )
    end
  end

  if opts.wiki_link_func == "prepend_note_id" then
    opts.wiki_link_func = builtin.wiki_link_id_prefix
  elseif opts.wiki_link_func == "prepend_note_path" then
    opts.wiki_link_func = builtin.wiki_link_path_prefix
  elseif opts.wiki_link_func == "use_path_only" then
    opts.wiki_link_func = builtin.wiki_link_path_only
  elseif opts.wiki_link_func == "use_alias_only" then
    opts.wiki_link_func = builtin.wiki_link_alias_only
  elseif type(opts.wiki_link_func) == "string" then
    error(string.format("invalid option '%s' for 'wiki_link_func'", opts.wiki_link_func))
  end

  if opts.completion ~= nil and opts.completion.preferred_link_style ~= nil then
    opts.preferred_link_style = opts.completion.preferred_link_style
    opts.completion.preferred_link_style = nil
    log.warn_once(
      "The config option 'completion.preferred_link_style' is deprecated, please use the top-level "
        .. "'preferred_link_style' instead."
    )
  end

  if opts.completion ~= nil and opts.completion.new_notes_location ~= nil then
    opts.new_notes_location = opts.completion.new_notes_location
    opts.completion.new_notes_location = nil
    log.warn_once(
      "The config option 'completion.new_notes_location' is deprecated, please use the top-level "
        .. "'new_notes_location' instead."
    )
  end

  if opts.detect_cwd ~= nil then
    opts.detect_cwd = nil
    log.warn_once(
      "The 'detect_cwd' field is deprecated and no longer has any affect.\n"
        .. "See https://github.com/epwalsh/obsidian.nvim/pull/366 for more details."
    )
  end

  if opts.open_app_foreground ~= nil then
    opts.open_app_foreground = nil
    log.warn_once [[The config option 'open_app_foreground' is deprecated, please use the `func` field in `open` module:

```lua
{
  open = {
    func = function(uri)
      vim.ui.open(uri, { cmd = { "open", "-a", "/Applications/Obsidian.app" } })
    end
  }
}
```]]
  end

  if opts.use_advanced_uri ~= nil then
    opts.use_advanced_uri = nil
    log.warn_once [[The config option 'use_advanced_uri' is deprecated, please use in `open` module instead]]
  end

  if opts.overwrite_mappings ~= nil then
    log.warn_once "The 'overwrite_mappings' config option is deprecated and no longer has any affect."
    opts.overwrite_mappings = nil
  end

  ---@diagnostic disable-next-line: undefined-field
  if opts.mappings ~= nil then
    log.warn_once [[The 'mappings' config option is deprecated and no longer has any affect.
See: https://github.com/obsidian-nvim/obsidian.nvim/wiki/Keymaps]]
    opts.overwrite_mappings = nil
  end

  if opts.tags ~= nil then
    log.warn_once "The 'tags' config option is deprecated and no longer has any affect."
    opts.tags = nil
  end

  if opts.templates and opts.templates.subdir then
    opts.templates.folder = opts.templates.subdir
    opts.templates.subdir = nil
  end

  if opts.ui and opts.ui.checkboxes then
    log.warn_once [[The 'ui.checkboxes' no longer effect the way checkboxes are ordered, use `checkbox.order`. See: https://github.com/obsidian-nvim/obsidian.nvim/issues/262]]
  end

  if opts.image_name_func then
    if opts.attachments == nil then
      opts.attachments = {}
    end
    opts.attachments.img_name_func = opts.image_name_func
    opts.image_name_func = nil
  end

  if opts.statusline and opts.statusline.enabled then
    deprecate(
      "statusline.{enabled,format} and vim.g.obsidian",
      "footer.{enabled,format}, see https://github.com/obsidian-nvim/obsidian.nvim/wiki/Statusline",
      "4.0"
    )
  end

  if opts.note_frontmatter_func then
    opts.frontmatter = opts.frontmatter or {}
    opts.frontmatter.func = opts.note_frontmatter_func
    opts.note_frontmatter_func = nil
    deprecate("note_frontmatter_func", "frontmatter.func", "4.0")
  end

  if opts.disable_frontmatter ~= nil then
    opts.frontmatter = opts.frontmatter or {}
    local disable_frontmatter = opts.disable_frontmatter
    if type(disable_frontmatter) == "boolean" then
      opts.frontmatter.enabled = not disable_frontmatter
    elseif type(disable_frontmatter) == "function" then
      opts.frontmatter.enabled = function(fname)
        return not disable_frontmatter(fname)
      end
    end
    opts.disable_frontmatter = nil
    deprecate("disable_frontmatter", "frontmatter.enabled", "4.0")
  end

  if opts.search_max_lines ~= nil then
    opts.search = opts.search or {}
    opts.search.max_lines = opts.search_max_lines
    opts.search_max_lines = nil
    deprecate("top-level 'search_max_lines'", "search.max_lines", "3.16")
  end

  if opts.sort_by ~= nil then
    opts.search = opts.search or {}
    opts.search.sort_by = opts.sort_by
    opts.sort_by = nil
    deprecate("top-level 'sort_by'", "search.sort_by", "3.16")
  end

  if opts.sort_reversed ~= nil then
    opts.search = opts.search or {}
    opts.search.sort_reversed = opts.sort_reversed
    opts.sort_reversed = nil
    deprecate("top-level 'sort_reversed'", "search.sort_reversed", "3.16")
  end

  ---@diagnostic disable-next-line: undefined-field
  if opts.attachments and opts.attachments.img_folder then
    ---@diagnostic disable-next-line: undefined-field
    opts.attachments.folder = opts.attachments.img_folder
    opts.attachments.img_folder = nil
    deprecate("attachments.img_folder", "attachments.folder", "3.16")
  end

  if opts.follow_url_func then
    opts.follow_url_func = nil
    deprecate(
      "follow_url_func",
      "vim.ui.open, see https://github.com/obsidian-nvim/obsidian.nvim/wiki/Attachment",
      "3.16"
    )
  end

  if opts.follow_img_func then
    opts.follow_img_func = nil
    deprecate(
      "follow_img_func",
      "vim.ui.open, see https://github.com/obsidian-nvim/obsidian.nvim/wiki/Attachment",
      "3.16"
    )
  end

  --------------------------
  -- Merge with defaults. --
  --------------------------

  opts = tbl_override(defaults, opts)

  opts.backlinks = tbl_override(defaults.backlinks, opts.backlinks)
  opts.completion = tbl_override(defaults.completion, opts.completion)
  opts.picker = tbl_override(defaults.picker, opts.picker)
  opts.daily_notes = tbl_override(defaults.daily_notes, opts.daily_notes)
  opts.templates = tbl_override(defaults.templates, opts.templates)
  opts.ui = tbl_override(defaults.ui, opts.ui)
  opts.attachments = tbl_override(defaults.attachments, opts.attachments)
  opts.statusline = tbl_override(defaults.statusline, opts.statusline)
  opts.footer = tbl_override(defaults.footer, opts.footer)
  opts.open = tbl_override(defaults.open, opts.open)
  opts.checkbox = tbl_override(defaults.checkbox, opts.checkbox)
  opts.comment = tbl_override(defaults.comment, opts.comment)
  opts.frontmatter = tbl_override(defaults.frontmatter, opts.frontmatter)

  ---------------
  -- Validate. --
  ---------------

  if opts.legacy_commands then
    deprecate(
      "legacy_commands",
      [[move from commands like `ObsidianBacklinks` to `Obsidian backlinks`
and set `opts.legacy_commands` to false to get rid of this warning.
see https://github.com/obsidian-nvim/obsidian.nvim/wiki/Commands for details.
    ]],
      "4.0"
    )
  end

  if opts.sort_by ~= nil and not vim.tbl_contains(vim.tbl_values(config.SortBy), opts.sort_by) then
    error("Invalid 'sort_by' option '" .. opts.sort_by .. "' in obsidian.nvim config.")
  end

  if not util.islist(opts.workspaces) then
    error "Invalid obsidian.nvim config, the 'config.workspaces' should be an array/list."
  end

  -- Convert dir to workspace format.
  if opts.dir ~= nil then
    table.insert(opts.workspaces, 1, { path = opts.dir })
  end

  return opts
end

return config
