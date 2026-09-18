local M = {}
local types = require "obsidian.types"

---@param errors string[]
---@param name string
---@param value any
---@param validator vim.validate.Validator
---@param optional? boolean
---@param message? string
---@return boolean
local function check(errors, name, value, validator, optional, message)
  local success, validation_error = pcall(vim.validate, name, value, validator, optional, message)
  if not success then
    errors[#errors + 1] = tostring(validation_error)
  end
  return success
end

---@param values any[]
---@return fun(value: any): boolean
local function one_of(values)
  return function(value)
    return vim.list_contains(values, value)
  end
end

---@param values any[]
---@return string
local function choices(values)
  local out = vim.tbl_map(vim.inspect, values)
  table.sort(out)
  return "one of " .. table.concat(out, ", ")
end

---@param errors string[]
---@param prefix string
---@param tbl table
---@param specs [string, vim.validate.Validator, string?][]
local function fields(errors, prefix, tbl, specs)
  for _, spec in ipairs(specs) do
    local key, validator, message = spec[1], spec[2], spec[3]
    local value = tbl[key]
    -- vim.NIL in user options explicitly removes a default during normalization.
    if value ~= vim.NIL then
      check(errors, prefix .. "." .. key, value, validator, true, message)
    end
  end
end

---@param errors string[]
---@param name string
---@param value any
---@param validator vim.validate.Validator
---@param message? string
local function list_of(errors, name, value, validator, message)
  if value == vim.NIL or value == nil then
    return
  end
  if not check(errors, name, value, vim.islist, false, "list") then
    return
  end
  for i, item in ipairs(value) do
    check(errors, string.format("%s[%d]", name, i), item, validator, false, message)
  end
end

---@param errors string[]
---@param name string
---@param value any
---@param specs [string, vim.validate.Validator, string?][]
local function nested_fields(errors, name, value, specs)
  if value == nil then
    return
  end
  if check(errors, name, value, "table") then
    fields(errors, name, value, specs)
  end
end

local integer = function(value)
  return type(value) == "number" and value % 1 == 0
end

local picker_names = vim.tbl_values(types.Picker)
local sort_values = vim.tbl_values(types.SortBy)
local open_strategies = vim.tbl_values(types.OpenStrategy)
local link_styles = vim.tbl_values(types.LinkStyle)
local link_formats = vim.tbl_values(types.LinkFormat)
local new_notes_locations = vim.tbl_values(types.NewNotesLocation)
local sync_triggers = vim.tbl_values(types.SyncTrigger)
local sync_modes = vim.tbl_values(types.SyncMode)
local conflict_strategies = vim.tbl_values(types.ConflictStrategy)
local sync_file_types = vim.tbl_values(types.SyncFileType)
local sync_config_categories = vim.tbl_values(types.SyncConfigCategory)

local config_sections = {
  "attachments",
  "backlinks",
  "cache",
  "checkbox",
  "comment",
  "completion",
  "daily_notes",
  "file",
  "footer",
  "frontmatter",
  "link",
  "note",
  "open",
  "picker",
  "search",
  "statusline",
  "sync",
  "templates",
  "ui",
  "unique_note",
}

---Validate only the structure needed to safely migrate and merge user options.
---@param opts any
---@return string[] errors
function M.validate_shape(opts)
  local errors = {}
  if not check(errors, "config", opts, "table") then
    return errors
  end
  for _, key in ipairs(config_sections) do
    check(errors, key, opts[key], "table", true)
  end
  return errors
end

---@param errors string[]
---@param opts table
---@param skip_overrides? boolean
local function validate_workspaces(errors, opts, skip_overrides)
  local workspaces = opts.workspaces
  if workspaces == nil or workspaces == vim.NIL then
    return
  end
  if not check(errors, "workspaces", workspaces, vim.islist, false, "list") then
    return
  end
  for i, workspace in ipairs(workspaces) do
    local name = string.format("workspaces[%d]", i)
    if check(errors, name, workspace, "table") then
      fields(errors, name, workspace, {
        { "path", { "string", "table", "callable" } },
        { "name", "string" },
        { "strict", "boolean" },
        { "overrides", "table" },
      })
      if not skip_overrides and type(workspace.overrides) == "table" then
        for _, issue in ipairs(M.validate(workspace.overrides, true)) do
          errors[#errors + 1] = name .. ".overrides." .. issue:gsub("^config%.", "")
        end
      end
    end
  end
end

---@param errors string[]
---@param name string
---@param value any
local function validate_char_spec(errors, name, value)
  nested_fields(errors, name, value, {
    { "char", "string" },
    { "hl_group", "string" },
  })
end

---@param errors string[]
---@param opts table
local function validate_ui(errors, opts)
  local ui = opts.ui
  if ui == nil then
    return
  end
  if not check(errors, "ui", ui, "table") then
    return
  end
  fields(errors, "ui", ui, {
    { "enable", "boolean" },
    { "enabled", "boolean" },
    { "ignore_conceal_warn", "boolean" },
    { "update_debounce", integer, "integer" },
    { "max_file_length", integer, "integer" },
    { "checkboxes", "table" },
    { "hl_groups", "table" },
  })
  if type(ui.checkboxes) == "table" then
    for key, spec in pairs(ui.checkboxes) do
      validate_char_spec(errors, string.format("ui.checkboxes[%s]", vim.inspect(key)), spec)
    end
  end
  validate_char_spec(errors, "ui.bullets", ui.bullets)
  validate_char_spec(errors, "ui.external_link_icon", ui.external_link_icon)
  for _, key in ipairs { "reference_text", "highlight_text", "tags", "block_ids" } do
    nested_fields(errors, "ui." .. key, ui[key], { { "hl_group", "string" } })
  end
  if type(ui.hl_groups) == "table" then
    for key, value in pairs(ui.hl_groups) do
      check(errors, "ui.hl_groups." .. tostring(key), value, "table")
    end
  end
end

---@param errors string[]
---@param opts table
local function validate_templates(errors, opts)
  local templates = opts.templates
  if templates == nil then
    return
  end
  if not check(errors, "templates", templates, "table") then
    return
  end
  fields(errors, "templates", templates, {
    { "enabled", "boolean" },
    { "folder", { "string", "table" } },
    { "date_format", "string" },
    { "time_format", "string" },
    { "substitutions", "table" },
    { "customizations", "table" },
  })
  if type(templates.substitutions) == "table" then
    for key, value in pairs(templates.substitutions) do
      check(errors, "templates.substitutions." .. tostring(key), value, { "string", "callable" })
    end
  end
  if type(templates.customizations) == "table" then
    for key, value in pairs(templates.customizations) do
      local name = "templates.customizations." .. tostring(key)
      if check(errors, name, value, "table") then
        fields(errors, name, value, {
          { "notes_subdir", "string" },
          { "note_id_func", "callable" },
        })
      end
    end
  end
end

---@param errors string[]
---@param opts table
local function validate_sync(errors, opts)
  local sync = opts.sync
  if sync == nil then
    return
  end
  if not check(errors, "sync", sync, "table") then
    return
  end
  fields(errors, "sync", sync, {
    { "enabled", "boolean" },
    { "backend", "string" },
    { "trigger", one_of(sync_triggers), choices(sync_triggers) },
    { "mode", one_of(sync_modes), choices(sync_modes) },
    { "conflict_strategy", one_of(conflict_strategies), choices(conflict_strategies) },
    { "config_dir", "string" },
    { "device_name", "string" },
  })
  list_of(errors, "sync.file_types", sync.file_types, one_of(sync_file_types), choices(sync_file_types))
  list_of(errors, "sync.configs", sync.configs, one_of(sync_config_categories), choices(sync_config_categories))
  list_of(errors, "sync.excluded_folders", sync.excluded_folders, "string")
end

---@param errors string[]
---@param opts table
local function validate_callbacks(errors, opts)
  nested_fields(errors, "callbacks", opts.callbacks, {
    { "post_setup", "callable" },
    { "create_note", "callable" },
    { "enter_note", "callable" },
    { "leave_note", "callable" },
    { "pre_write_note", "callable" },
    { "add_attachment", "callable" },
    { "post_set_workspace", "callable" },
  })
  nested_fields(errors, "resolvers", opts.resolvers, {
    { "attachment", "callable" },
    { "date", "callable" },
    { "hints", "callable" },
  })
end

---Validate an obsidian.nvim configuration without modifying it.
---@param opts any
---@param skip_workspace_overrides? boolean
---@return string[] errors
function M.validate(opts, skip_workspace_overrides)
  local errors = {}
  if not check(errors, "config", opts, "table") then
    return errors
  end

  fields(errors, "config", opts, {
    { "log_level", integer, "integer" },
    { "notes_subdir", "string" },
    { "new_notes_location", one_of(new_notes_locations), choices(new_notes_locations) },
    { "note_id_func", "callable" },
    { "note_path_func", "callable" },
    { "open_notes_in", one_of(open_strategies), choices(open_strategies) },
    { "legacy_commands", "boolean" },
  })
  validate_workspaces(errors, opts, skip_workspace_overrides)

  nested_fields(errors, "statusline", opts.statusline, {
    { "format", "string" },
    { "enabled", "boolean" },
  })

  if type(opts.link) == "table" then
    local style = opts.link.style
    if style ~= nil and style ~= vim.NIL then
      if type(style) == "function" then
        check(errors, "link.style", style, "callable")
      else
        check(errors, "link.style", style, one_of(link_styles), false, choices(link_styles))
      end
    end
    fields(errors, "link", opts.link, {
      { "format", one_of(link_formats), choices(link_formats) },
      { "auto_update", "boolean" },
    })
  elseif opts.link ~= nil then
    check(errors, "link", opts.link, "table")
  end

  nested_fields(errors, "note", opts.note, { { "template", "string" } })

  if type(opts.file) == "table" then
    list_of(errors, "file.ignore_filters", opts.file.ignore_filters, "string")
  elseif opts.file ~= nil then
    check(errors, "file", opts.file, "table")
  end

  if type(opts.frontmatter) == "table" then
    fields(errors, "frontmatter", opts.frontmatter, {
      { "enabled", { "boolean", "callable" } },
      { "func", "callable" },
      { "sort", { "table", "callable", "boolean" } },
    })
    if type(opts.frontmatter.sort) == "table" and opts.frontmatter.sort ~= vim.NIL then
      list_of(errors, "frontmatter.sort", opts.frontmatter.sort, "string")
    end
  elseif opts.frontmatter ~= nil then
    check(errors, "frontmatter", opts.frontmatter, "table")
  end

  validate_templates(errors, opts)
  nested_fields(errors, "backlinks", opts.backlinks, { { "parse_headers", "boolean" } })
  nested_fields(errors, "completion", opts.completion, {
    { "min_chars", integer, "integer" },
    { "match_case", "boolean" },
    { "create_new", "boolean" },
  })

  if type(opts.picker) == "table" then
    fields(errors, "picker", opts.picker, {
      { "name", one_of(picker_names), choices(picker_names) },
      { "note_mappings", "table" },
      { "tag_mappings", "table" },
    })
    if type(opts.picker.note_mappings) == "table" then
      fields(errors, "picker.note_mappings", opts.picker.note_mappings, {
        { "new", "string" },
        { "insert_link", "string" },
        { "bookmark", "string" },
      })
    end
    if type(opts.picker.tag_mappings) == "table" then
      fields(errors, "picker.tag_mappings", opts.picker.tag_mappings, {
        { "tag_note", "string" },
        { "insert_tag", "string" },
      })
    end
  elseif opts.picker ~= nil then
    check(errors, "picker", opts.picker, "table")
  end

  if type(opts.search) == "table" then
    local sort_by = opts.search.sort_by
    if sort_by ~= nil and sort_by ~= vim.NIL and sort_by ~= false then
      check(errors, "search.sort_by", sort_by, one_of(sort_values), false, choices(sort_values) .. " or false")
    end
    fields(errors, "search", opts.search, {
      { "sort_reversed", "boolean" },
      { "max_lines", integer, "integer" },
    })
  elseif opts.search ~= nil then
    check(errors, "search", opts.search, "table")
  end

  if type(opts.daily_notes) == "table" then
    fields(errors, "daily_notes", opts.daily_notes, {
      { "enabled", "boolean" },
      { "folder", "string" },
      { "date_format", "string" },
      { "alias_format", "string" },
      { "template", "string" },
      { "workdays_only", "boolean" },
      {
        "start_of_week",
        function(value)
          return integer(value) and value >= 0 and value <= 6
        end,
        "integer between 0 and 6",
      },
    })
    list_of(errors, "daily_notes.default_tags", opts.daily_notes.default_tags, "string")
  elseif opts.daily_notes ~= nil then
    check(errors, "daily_notes", opts.daily_notes, "table")
  end

  validate_ui(errors, opts)
  nested_fields(errors, "unique_note", opts.unique_note, {
    { "enabled", "boolean" },
    { "format", { "string", "callable" } },
    { "folder", "string" },
    { "template", "string" },
  })
  nested_fields(errors, "attachments", opts.attachments, {
    { "folder", "string" },
    { "img_name_func", "callable" },
    { "img_text_func", "callable" },
    { "confirm_img_paste", "boolean" },
  })
  validate_sync(errors, opts)
  validate_callbacks(errors, opts)
  nested_fields(errors, "footer", opts.footer, {
    { "enabled", "boolean" },
    { "format", "string" },
    { "hl_group", "string" },
    {
      "separator",
      function(value)
        return type(value) == "string" or value == false
      end,
      "string or false",
    },
  })

  if type(opts.open) == "table" then
    fields(errors, "open", opts.open, {
      { "use_advanced_uri", "boolean" },
      { "func", "callable" },
    })
    list_of(errors, "open.schemes", opts.open.schemes, "string")
  elseif opts.open ~= nil then
    check(errors, "open", opts.open, "table")
  end

  if type(opts.checkbox) == "table" then
    fields(errors, "checkbox", opts.checkbox, {
      { "enabled", "boolean" },
      { "create_new", "boolean" },
    })
    list_of(errors, "checkbox.order", opts.checkbox.order, "string")
  elseif opts.checkbox ~= nil then
    check(errors, "checkbox", opts.checkbox, "table")
  end

  nested_fields(errors, "comment", opts.comment, { { "enabled", "boolean" } })
  nested_fields(errors, "slides", opts.slides, { { "enabled", "boolean" } })
  nested_fields(errors, "cache", opts.cache, {
    { "enabled", "boolean" },
    { "backend", "string" },
  })

  return errors
end

---@param errors string[]
---@return string
function M.format_errors(errors)
  return "Invalid obsidian.nvim configuration:\n- " .. table.concat(errors, "\n- ")
end

return M
