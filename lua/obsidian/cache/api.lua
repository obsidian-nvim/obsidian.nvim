local util = require "obsidian.util"
local attachment = require "obsidian.attachment"
local icons = require "obsidian.icons"
local link = require "obsidian.link"
local api = require "obsidian.api"
local picker_util = require "obsidian.picker.util"

local M = {}

---@class obsidian.cache.ResolveNotesOpts
---@field dir string|obsidian.Path|?
---@field include_templates boolean|?
---@field notes obsidian.note.LoadOpts|?

---@param value string
---@param query string
---@return boolean
local function fuzzy_matches(value, query)
  return #vim.fn.matchfuzzy({ value:lower() }, query) > 0
end

---@param path string
---@param row table
---@param query string
---@return boolean
local function note_matches(path, row, query)
  local stem = vim.fn.fnamemodify(path, ":t:r")
  if fuzzy_matches(stem, query) then
    return true
  end

  for _, alias in ipairs(row.aliases or {}) do
    if fuzzy_matches(tostring(alias), query) then
      return true
    end
  end

  return false
end

---@param path string
---@param row table
---@param load_opts obsidian.note.LoadOpts
---@return obsidian.Note
local function note_from_cache(path, row, load_opts)
  local Note = require "obsidian.note"
  local note = Note.from_cache(path, row)

  if load_opts.collect_anchor_links or load_opts.collect_blocks or load_opts.collect_sections then
    local loaded = Note.from_file(path, load_opts)
    note.anchor_links = loaded.anchor_links
    note.blocks = loaded.blocks
    note.sections = loaded.sections
  end

  return note
end

---Resolve cached notes using fuzzy matches against filename stems and aliases.
---
---The cache must be ready before calling this function. Use `cache.when_ready()`
---when calling it from an asynchronous UI flow.
---
---@param query string
---@param opts obsidian.cache.ResolveNotesOpts|?
---@return obsidian.Note[]
M.resolve_notes = function(query, opts)
  local cache = require "obsidian.cache"
  assert(cache.is_ready(), "cache not ready")

  opts = opts or {}
  local dir = vim.fs.normalize(tostring(opts.dir or Obsidian.dir))
  local query_lower = vim.trim(query):lower()
  if query_lower == "" then
    return {}
  end

  local templates_dir
  if
    opts.include_templates ~= true
    and Obsidian.opts
    and Obsidian.opts.templates
    and Obsidian.opts.templates.folder
  then
    templates_dir = api.templates_dir()
  end

  local rows = {}
  local paths = {}
  for path, row in pairs(cache.notes.all()) do
    if
      row.attachment ~= true
      and util.is_subpath(path, dir)
      and (templates_dir == nil or not util.is_subpath(path, tostring(templates_dir)))
      and note_matches(path, row, query_lower)
    then
      paths[#paths + 1] = path
      rows[path] = row
    end
  end
  table.sort(paths)

  local notes = {}
  local load_opts = opts.notes or {}
  for _, path in ipairs(paths) do
    local ok, note = pcall(note_from_cache, path, rows[path], load_opts)
    if ok then
      notes[#notes + 1] = note
    end
  end
  return notes
end

---@param target string
---@return boolean
local function is_attachment_target(target)
  return attachment.is_attachment_path(target:lower())
end

---@param target string?
---@return boolean
local function is_external_target(target)
  return target == nil or target == "" or target:match "^%a[%w+.-]*:" ~= nil
end

---@param target string
---@return string
local function normalize_link_target(target)
  target = vim.uri_decode(target):gsub("\\", "/")
  while vim.startswith(target, "./") do
    target = target:sub(3)
  end
  return (target:gsub("^/+", ""))
end

---@param path string
---@param lookup table<string, boolean>
local function add_lookup_path(path, lookup)
  local cache = require "obsidian.cache"
  local rel_path = cache.notes.rel_path(path)
  local rel_path_no_ext = rel_path:gsub("%.md$", "")
  local basename = vim.fn.fnamemodify(path, ":t")
  for _, key in ipairs {
    rel_path,
    rel_path_no_ext,
    basename,
    vim.fn.fnamemodify(path, ":t:r"),
  } do
    lookup[key:lower()] = true
  end
end

---@param target string
---@param lookup table<string, boolean>
---@return boolean
local function target_exists(target, lookup)
  local normalized = normalize_link_target(target)
  local normalized_no_ext = normalized:gsub("%.md$", "")
  for _, key in ipairs { normalized, normalized_no_ext, normalized .. ".md" } do
    if lookup[key:lower()] then
      return true
    end
  end
  return false
end

---@param is_attachment boolean
---@param missing boolean
---@param references obsidian.NoteCreationReference[]?
---@param target string?
---@return obsidian.PickerEntryUserData
local function entry_user_data(is_attachment, missing, references, target)
  return { attachment = is_attachment, missing = missing, references = references, target = target }
end

---@param opts obsidian.PickerFindOpts|?
---@return boolean handled
M.find_files = function(opts)
  opts = opts or {}
  local cache = require "obsidian.cache"
  if not opts.use_cache or not cache.is_enabled() or opts.include_non_markdown then
    return false
  end

  local show_existing_only = opts.show_existing_only ~= false
  local show_attachments = opts.show_attachments == true
  local dir = opts.dir and vim.fs.normalize(tostring(opts.dir)) or vim.fs.normalize(tostring(Obsidian.dir))
  if not util.is_subpath(dir, tostring(Obsidian.dir)) then
    return false
  end

  cache.when_ready(function()
    local query = opts.query and vim.trim(opts.query) or nil
    if query == "" then
      query = nil
    end
    local query_lower = query and string.lower(query) or nil

    ---@type obsidian.PickerEntry[]
    local entries = {}
    local lookup = {}
    ---@type table<string, obsidian.PickerEntry>
    local missing_entries = {}
    local all = cache.notes.all()

    ---@param text string
    ---@param path string
    ---@param user_data obsidian.PickerEntryUserData
    ---@return obsidian.PickerEntry?
    local function add_entry(text, path, user_data)
      if query_lower and not string.find(string.lower(text), query_lower, 1, true) then
        return
      end
      local entry = {
        text = text,
        filename = path,
        user_data = user_data,
      }
      entries[#entries + 1] = entry
      return entry
    end

    for path, note in pairs(all) do
      add_lookup_path(path, lookup)
      for _, alias in ipairs(note.aliases or {}) do
        lookup[alias:lower()] = true
      end
    end

    for path, note in pairs(all) do
      local is_attachment = note.attachment == true or is_attachment_target(path)
      if util.is_subpath(path, dir) and (show_attachments or not is_attachment) then
        local rel_path = cache.notes.rel_path(path):gsub("%.md$", "")
        local user_data = entry_user_data(is_attachment, false)
        add_entry(rel_path, path, user_data)
        for _, alias in ipairs(note.aliases or {}) do
          add_entry(rel_path .. " | " .. alias, path, user_data)
        end
      end
    end

    if not show_existing_only then
      for path, note in pairs(all) do
        for _, outgoing in ipairs(note.links_out or {}) do
          local target = outgoing.target
          if not is_external_target(target) and not target_exists(target, lookup) then
            local missing_is_attachment = is_attachment_target(target)
            if show_attachments or not missing_is_attachment then
              local target_path = link.missing_link_path(target, path)
              if target_path and util.is_subpath(target_path, dir) then
                local missing_key = missing_is_attachment and target_path or normalize_link_target(target):lower()
                ---@type obsidian.NoteCreationReference
                local reference = {
                  filename = path,
                  lnum = outgoing.line or 1,
                  col = outgoing.col or 1,
                  raw = outgoing.raw or target,
                }
                local entry = missing_entries[missing_key]
                if entry then
                  local data = entry.user_data
                  data.references[#data.references + 1] = reference
                else
                  local text = normalize_link_target(target)
                  local added = add_entry(
                    text,
                    target_path,
                    entry_user_data(missing_is_attachment, true, { reference }, normalize_link_target(target))
                  )
                  if added then
                    missing_entries[missing_key] = added
                  end
                end
              end
            end
          end
        end
      end
    end

    local pick_query = opts.query
    if query and #entries > 0 then
      pick_query = nil
    end

    ---@param entry obsidian.PickerEntry
    ---@return string
    local format_picker_entry = function(entry)
      local icon = icons.get_icon(entry)
      local text = entry.text or ""
      return icon .. " " .. text
    end

    ---@param entry obsidian.PickerEntry
    ---@return obsidian.ui_select_preview_spec
    local function preview_picker_entry(entry)
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].bufhidden = "wipe"

      local data = entry.user_data or {}
      if data.missing then
        local references = vim.deepcopy(data.references or {})
        table.sort(references, function(a, b)
          local a_path = cache.notes.rel_path(a.filename)
          local b_path = cache.notes.rel_path(b.filename)
          if a_path ~= b_path then
            return a_path < b_path
          elseif a.lnum ~= b.lnum then
            return a.lnum < b.lnum
          else
            return a.col < b.col
          end
        end)

        local lines = {}
        for i, reference in ipairs(references) do
          if i > 1 then
            lines[#lines + 1] = ""
          end
          lines[#lines + 1] = ("%s:%d:%d"):format(
            cache.notes.rel_path(reference.filename),
            reference.lnum,
            reference.col
          )
          lines[#lines + 1] = ""
          lines[#lines + 1] = "```markdown"
          lines[#lines + 1] = reference.raw
          lines[#lines + 1] = "```"
        end
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.bo[buf].filetype = "markdown"
      elseif entry.filename then
        local ok, lines = pcall(vim.fn.readfile, entry.filename, "", 1000)
        if not ok then
          lines = { entry.filename }
        end
        if not pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, lines) then
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, { entry.filename })
        end
        local filetype = vim.filetype.match { filename = entry.filename }
        if filetype then
          vim.bo[buf].filetype = filetype
        end
      end

      return { buf = buf }
    end

    local picker = require "obsidian.picker"

    picker.select(entries, {
      prompt = opts.prompt_title,
      allow_multiple = true,
      -- The cache has already applied the initial query case-insensitively.
      -- Don't pass it through, since some pickers would filter again case-sensitively.
      query = pick_query,
      query_mappings = opts.query_mappings,
      selection_mappings = opts.selection_mappings,
      format_item = format_picker_entry,
      preview_item = preview_picker_entry,
    }, function(items)
      local paths = vim.tbl_filter(
        function(path)
          return path ~= nil
        end,
        vim.tbl_map(function(item)
          return item["filename"]
        end, items)
      )
      if opts.callback then
        opts.callback(paths)
        return
      end

      local notes = {}
      for _, item in ipairs(items) do
        local path = item.filename
        local data = item.user_data or {}
        local is_missing_attachment = data.attachment and data.missing
        if path and is_missing_attachment then
          require("obsidian.actions").add_attachment(nil, {
            insert = false,
            bufnr = require("obsidian.picker").state.calling_bufnr,
            dst = path,
          })
        elseif path and data.attachment then
          vim.ui.open(path)
        elseif path and data.missing then
          local choice = api.confirm("How to handle missing reference?", "&Create New Note\n&Open References")
          if choice == "Create New Note" then
            local location = data.target or cache.notes.rel_path(path):gsub("%.md$", "")
            api.create_new_note(location, function(locations)
              if locations and locations[1] then
                api.open_note(vim.uri_to_fname(locations[1].uri))
              end
            end, { references = data.references })
          elseif choice == "Open References" then
            picker.select(data.references, { prompt = "Unresolved References" }, function(choices)
              picker_util.open_notes(choices)
            end)
          end
        elseif path then
          notes[#notes + 1] = item
        end
      end
      picker_util.open_notes(notes)
    end)
  end)

  return true
end

return M
