local util = require "obsidian.util"
local validator = require "obsidian.config.validate"
local config = {}

config.default = require "obsidian.config.default"
config.validate = validator.validate

local function assert_no_errors(errors)
  if #errors > 0 then
    error(validator.format_errors(errors), 0)
  end
end

local function assert_valid(opts)
  assert_no_errors(validator.validate(opts))
end

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
  assert_no_errors(validator.validate_shape(opts))

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

  assert_valid(opts)

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

  -- Convert dir to workspace format.
  if opts.dir ~= nil then
    table.insert(opts.workspaces, 1, { path = opts.dir })
  end

  return opts
end

return config
