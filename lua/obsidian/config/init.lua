local util = require "obsidian.util"
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

---@enum obsidian.config.Picker
config.Picker = {
  telescope = "telescope.nvim",
  fzf_lua = "fzf-lua",
  mini = "mini.pick",
  snacks = "snacks.picker",
}

config.default = require "obsidian.config.default"

local tbl_override = function(defaults, overrides, list_fields)
  local out = vim.tbl_deep_extend("force", defaults, overrides)
  for k, v in pairs(out) do
    if v == vim.NIL then
      out[k] = nil
    elseif list_fields and list_fields[k] then
      out[k] = vim.deepcopy(defaults[k])
      for _, item in ipairs(overrides[k] or {}) do
        table.insert(out[k], item)
      end
    end
  end
  return out
end

--- Normalize options.
---
---@param opts obsidian.config
---@param defaults obsidian.config.Internal|?
---
---@return obsidian.config.Internal
config.normalize = function(opts, defaults)
  opts = opts or {}

  if not defaults then
    defaults = config.default
  end

  opts = require "obsidian.config.removed"(opts, defaults)

  --------------------------
  -- Merge with defaults. --
  --------------------------

  opts = tbl_override(defaults, opts)

  opts.backlinks = tbl_override(defaults.backlinks, opts.backlinks)
  opts.completion = tbl_override(defaults.completion, opts.completion)
  opts.picker = tbl_override(defaults.picker, opts.picker)
  opts.quick_switch = tbl_override(defaults.quick_switch, opts.quick_switch)
  opts.daily_notes = tbl_override(defaults.daily_notes, opts.daily_notes)
  opts.templates = tbl_override(defaults.templates, opts.templates)
  opts.ui = tbl_override(defaults.ui, opts.ui)
  opts.attachments = tbl_override(defaults.attachments, opts.attachments)
  opts.statusline = tbl_override(defaults.statusline, opts.statusline)
  opts.footer = tbl_override(defaults.footer, opts.footer)
  opts.open = tbl_override(defaults.open, opts.open, { schemes = true })
  opts.checkbox = tbl_override(defaults.checkbox, opts.checkbox)
  opts.cache = tbl_override(defaults.cache, opts.cache)
  opts.comment = tbl_override(defaults.comment, opts.comment)
  opts.frontmatter = tbl_override(defaults.frontmatter, opts.frontmatter)
  opts.search = tbl_override(defaults.search, opts.search)
  opts.note = tbl_override(defaults.note, opts.note)
  opts.link = tbl_override(defaults.link, opts.link)
  opts.unique_note = tbl_override(defaults.unique_note, opts.unique_note)
  opts.sync = tbl_override(defaults.sync, opts.sync)
  opts.file = tbl_override(defaults.file, opts.file)

  ---------------
  -- Validate. --
  ---------------

  if opts.legacy_commands then
    util.deprecate(
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

  local valid_link_styles = { "wiki", "markdown" }
  if
    opts.link ~= nil
    and opts.link.style ~= nil
    and type(opts.link.style) ~= "function"
    and not vim.tbl_contains(valid_link_styles, opts.link.style)
  then
    error("Invalid 'link.style' option '" .. tostring(opts.link.style) .. "' in obsidian.nvim config.")
  end

  local valid_link_formats = { "shortest", "relative", "absolute" }
  if opts.link ~= nil and opts.link.format ~= nil and not vim.tbl_contains(valid_link_formats, opts.link.format) then
    error("Invalid 'link.format' option '" .. tostring(opts.link.format) .. "' in obsidian.nvim config.")
  end

  if not vim.islist(opts.workspaces) then
    error "Invalid obsidian.nvim config, the 'config.workspaces' should be an array/list."
  end

  if opts.file and opts.file.ignore_filters ~= nil then
    if type(opts.file.ignore_filters) ~= "table" then
      error "Invalid obsidian.nvim config, 'file.ignore_filters' should be an array of strings."
    end
    for i, pattern in ipairs(opts.file.ignore_filters) do
      if type(pattern) ~= "string" then
        error(string.format("Invalid obsidian.nvim config, 'file.ignore_filters[%d]' should be a string.", i))
      end
    end
  end

  -- Convert dir to workspace format.
  if opts.dir ~= nil then
    table.insert(opts.workspaces, 1, { path = opts.dir })
  end

  return opts
end

return config
