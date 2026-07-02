--- *obsidian-api*
---
--- The Obsidian.nvim Lua API.
---
--- ==============================================================================
---
--- Table of contents
---
---@toc

local Path = require "obsidian.path"
local yaml = require "obsidian.yaml"
local log = require "obsidian.log"
local util = require "obsidian.util"
local text_insertion = require "obsidian.util.text_insertion"
local api = require "obsidian.api"
local Frontmatter = require "obsidian.frontmatter"
local search = require "obsidian.search"
local ignore = require "obsidian.ignore"
local Section = require "obsidian.section"
local Range = require "obsidian.range"

local SKIP_UPDATING_FRONTMATTER = { "README.md", "CONTRIBUTING.md", "CHANGELOG.md" }

local DEFAULT_MAX_LINES = 500

local function is_default_note_template(template)
  local default_template = require("obsidian.config.default").note.template
  return template ~= nil
    and default_template ~= nil
    and Path.new(template):resolve() == Path.new(default_template):resolve()
end

---@param section obsidian.Section
---@param parent obsidian.note.HeaderAnchor|?
---@param anchor string|?
---@return obsidian.note.HeaderAnchor
local function new_header_anchor(section, parent, anchor)
  local section_anchor = assert(section.anchor, "section anchor is required")
  local header = assert(section.header, "section header is required")
  local level = assert(section.level, "section level is required")

  return {
    anchor = anchor or section_anchor,
    line = section.heading_range.start_row + 1,
    header = header,
    level = level,
    parent = parent,
    section = section,
  }
end

--- A class that represents a note within a vault.
---
---@toc_entry obsidian.Note
---
---@class obsidian.Note
---
---@field id string
---@field title string readable name for note
---@field aliases string[]
---@field tags string[]
---@field contents string[]
---@field metadata table
---@field path obsidian.Path|?
---@field has_frontmatter boolean|?
---@field frontmatter_end_line integer|?
---@field anchor_links table<string, obsidian.note.HeaderAnchor>|?
---@field blocks table<string, obsidian.note.Block>?
---@field sections obsidian.Section[]|? document-ordered sections, the first one is always the preamble.
---@field alt_alias string|?
---@field bufnr integer|?
---@field template string|? Template name carried by the note. Used as the default `template` for `note:write` when no explicit value is passed.
local Note = {}

local load_contents = function(note)
  local contents = {}
  local path = tostring(rawget(note, "path"))
  if not path or not vim.uv.fs_stat(path) then
    return {}
  end
  for line in io.lines(path) do
    table.insert(contents, line)
  end
  return contents
end

local function coerce(v)
  if v == vim.NIL then
    return nil
  else
    return v
  end
end

---@param path table
---@param k string
---@param factory fun(path: obsidian.Note): any
---@private
local function cached_get(path, k, factory)
  local cache_key = "__" .. k
  local v = rawget(path, cache_key)
  if v == nil then
    v = factory(path)
    if v == nil then
      v = vim.NIL
    end
    path[cache_key] = v
  end
  return coerce(v)
end

Note.__index = function(self, k)
  local raw = rawget(Note, k)
  if raw then
    return raw
  end
  if k == "contents" then
    return cached_get(self, "contents", load_contents)
  end
end

Note.__tostring = function(self)
  return string.format("Note('%s')", self.id)
end

Note.is_note_obj = function(note)
  if getmetatable(note) == Note then
    return true
  else
    return false
  end
end

--- Generate a unique ID for a new note. This respects the user's `note_id_func` if configured,
--- otherwise falls back to generated a Zettelkasten style ID.
---
--- @param base_id? string
--- @param path? obsidian.Path
--- @param id_func (fun(title: string|?, path: obsidian.Path|?): string)
---@return string
local function generate_id(base_id, path, id_func)
  local new_id = id_func(base_id, path)
  if new_id == nil or string.len(new_id) == 0 then
    error(string.format("Your 'note_id_func' must return a non-empty string, got '%s'!", tostring(new_id)))
  end
  -- Remote '.md' suffix if it's there (we add that later).
  new_id = new_id:gsub("%.md$", "", 1)
  return new_id
end

--- Generate the file path for a new note given its ID, parent directory, and title.
--- This respects the user's `note_path_func` if configured, otherwise essentially falls back to
--- `note_opts.dir / (note_opts.id .. ".md")`.
---
---@param id string The note ID
---@param dir obsidian.Path The note path
---@return obsidian.Path
---@private
Note._generate_path = function(id, dir)
  ---@type obsidian.Path
  local path

  path = Path.new(Obsidian.opts.note_path_func { id = id, dir = dir })

  -- NOTE: `opts.dir` should always be absolute, but for extra safety we handle the case where
  if not path:is_absolute() and (dir:is_absolute() or not dir:is_parent_of(path)) then
    path = dir / path
  end

  -- TODO: automatically cleanup instead of call with_suffix in default and in cleanup

  -- Ensure there is only one ".md" suffix. This might arise if `note_path_func`
  -- supplies an unusual implementation returning something like /bad/note/id.md.md.md
  while path.filename:match "%.md$" do
    path.filename = path.filename:gsub("%.md$", "")
  end

  return path:with_suffix(".md", true)
end

--- Selects the strategy to use when resolving the note title, id, and path
---@param opts obsidian.note.NoteOpts The note creation options
---@return obsidian.note.NoteCreationOpts The strategy to use for creating the note
---@private
Note._get_creation_opts = function(opts)
  --- @type obsidian.note.NoteCreationOpts
  local ret = {
    notes_subdir = Obsidian.opts.notes_subdir,
    note_id_func = Obsidian.opts.note_id_func,
    new_notes_location = Obsidian.opts.new_notes_location,
  }

  if opts.template == nil then
    return ret
  end

  local resolve_template = require("obsidian.templates").resolve_template
  local success, template_path = pcall(resolve_template, opts.template, api.templates_dir())

  if not success then
    return ret
  end

  local stem = template_path.stem:lower()

  -- Check if the configuration has a custom key for this template
  for key, cfg in pairs(Obsidian.opts.templates.customizations or {}) do
    if key:lower() == stem then
      ret = {
        notes_subdir = cfg.notes_subdir or ret.notes_subdir,
        note_id_func = cfg.note_id_func or ret.note_id_func,
        new_notes_location = "notes_subdir",
      }
      break
    end
  end
  return ret
end

---@param s string
---@return string|?
---@return string|?
local parse_as_path = function(s)
  ---@type string|?
  local parent

  if s:match "%.md" then
    -- Remove suffix.
    s = s:sub(1, s:len() - 3)
  end

  -- Pull out any parent dirs from title.
  local parts = vim.split(s, "/")
  if #parts > 1 then
    s = parts[#parts]
    parent = table.concat(parts, "/", 1, #parts - 1)
  end

  if s == "" then
    return nil, parent
  else
    return s, parent
  end
end

--- Resolves the ID, and path for a new note.
---
---@param opts obsidian.note.NoteOpts Strategy for resolving note path and title
---@return string id
---@return obsidian.Path path
---@return string|? title
---@private
Note._resolve_id_path = function(opts)
  local id, dir = opts.id, opts.dir
  local creation_opts = Note._get_creation_opts(opts or {})

  if id then
    id = vim.trim(id)
    if id == "" then
      id = nil
    end
  end

  local parent
  if id then
    id, parent = parse_as_path(id)
  end

  -- Resolve base directory.
  ---@type obsidian.Path
  local base_dir
  if parent then
    base_dir = Path.new(vim.fs.joinpath(tostring(Obsidian.dir), parent))
  elseif dir ~= nil then
    base_dir = Path.new(dir)
    if not base_dir:is_absolute() then
      base_dir = Path.new(vim.fs.joinpath(tostring(Obsidian.dir), tostring(base_dir)))
    else
      base_dir = base_dir:resolve()
    end
  else
    local function is_in_vault(path)
      return path == Obsidian.dir or Obsidian.dir:is_parent_of(path)
    end

    local function is_in_daily_notes(path)
      local daily_notes_folder = Obsidian.opts.daily_notes.folder
      if daily_notes_folder == nil then
        return false
      end

      local daily_notes_dir = Path.new(vim.fs.joinpath(tostring(Obsidian.dir), daily_notes_folder))
      return path == daily_notes_dir or daily_notes_dir:is_parent_of(path)
    end

    if creation_opts.new_notes_location == "current_dir" then
      local bufname = vim.api.nvim_buf_get_name(0)
      local bufpath = bufname ~= "" and Path.new(bufname):resolve() or nil
      local cwd = Path.new(vim.fn.getcwd(0, 0)):resolve()

      if bufpath ~= nil and api.path_is_note(bufpath) then
        if not is_in_daily_notes(bufpath) then
          base_dir = assert(bufpath:parent())
        end
      elseif is_in_vault(cwd) and not is_in_daily_notes(cwd) then
        base_dir = cwd
      end
    end

    if base_dir == nil then
      base_dir = Obsidian.dir
      if creation_opts.notes_subdir ~= nil then
        base_dir = Path.new(vim.fs.joinpath(tostring(base_dir), creation_opts.notes_subdir))
      end
    end
  end

  -- Make sure `base_dir` is absolute at this point.
  assert(base_dir:is_absolute(), ("failed to resolve note directory '%s'"):format(base_dir))

  local title = opts.title or id

  -- Apply id transform
  if not (opts.verbatim and id) then
    id = generate_id(id, base_dir, creation_opts.note_id_func)
  end

  dir = base_dir

  -- Generate path.
  ---@cast id string
  local path = Note._generate_path(id, dir)

  return id, path, title
end

--- Creates a new note in memory.
---
--- The note is NOT written to disk. Call `note:write {}` after if you want the
--- file persisted; the `template` passed here is carried on the note and used
--- by `note:write` unless overridden.
---
--- @param opts obsidian.note.NoteOpts?
--- @return obsidian.Note
Note.create = function(opts)
  opts = opts or {}
  local new_id, path, title = Note._resolve_id_path(opts)
  opts = vim.tbl_extend("keep", opts, { aliases = {}, tags = {} })
  if rawget(opts, "should_write") then
    log.warn "`should_write` in Note.create is removed, call note:write instead"
  end

  local aliases = opts.aliases
  local note = Note.new(new_id, aliases, opts.tags, path, title)
  note.template = opts.template
  local callback_opts = { scope = opts.scope or "plain" }
  util.fire_callback("create_note", Obsidian.opts.callbacks.create_note, note, callback_opts)
  vim.api.nvim_exec_autocmds("User", {
    pattern = "ObsidianNoteCreate",
    data = { note = note, opts = callback_opts },
  })
  return note
end

--- Instantiates a new Note object
---
--- Keep in mind that you have to call `note:save(...)` to create/update the note on disk.
---
--- @param id string|number
--- @param aliases string[]|?
--- @param tags string[]|?
--- @param path string|obsidian.Path|?
--- @param title string|?
--- @return obsidian.Note
Note.new = function(id, aliases, tags, path, title)
  local self = {}
  self.id = id
  self.aliases = aliases and aliases or {}
  self.tags = tags and tags or {}
  self.path = path and Path.new(path) or nil
  self.title = title
  self.metadata = nil
  self.has_frontmatter = nil
  self.frontmatter_end_line = nil
  return setmetatable(self, Note)
end

--- Get markdown display info about the note.
---
---@param opts { label: string|?, anchor: obsidian.note.HeaderAnchor|?, block: obsidian.note.Block|? }|?
---
---@return string
Note.display_info = function(self, opts)
  opts = opts and opts or {}

  ---@type string[]
  local info = {}

  if opts.label ~= nil and string.len(opts.label) > 0 then
    info[#info + 1] = ("%s"):format(opts.label)
    info[#info + 1] = "--------"
  end

  if self.path ~= nil then
    info[#info + 1] = ("**path:** `%s`"):format(self.path)
  end

  info[#info + 1] = ("**id:** `%s`"):format(self.id)

  if #self.aliases > 0 then
    info[#info + 1] = ("**aliases:** '%s'"):format(table.concat(self.aliases, "', '"))
  end

  if #self.tags > 0 then
    info[#info + 1] = ("**tags:** `#%s`"):format(table.concat(self.tags, "`, `#"))
  end

  if opts.anchor or opts.block then
    info[#info + 1] = "--------"

    if opts.anchor then
      info[#info + 1] = ("...\n%s %s\n..."):format(string.rep("#", opts.anchor.level), opts.anchor.header)
    elseif opts.block then
      info[#info + 1] = ("...\n%s\n..."):format(opts.block.block)
    end
  end

  return table.concat(info, "\n")
end

--- Check if the note exists on the file system.
---
---@return boolean
Note.exists = function(self)
  ---@diagnostic disable-next-line: return-type-mismatch
  return self.path ~= nil and self.path:is_file()
end

--- Get the filename associated with the note.
---
---@return string|?
Note.fname = function(self)
  if self.path == nil then
    return nil
  else
    return vim.fs.basename(tostring(self.path))
  end
end

--- Get file uri
---
---@return string?
Note.uri = function(self)
  assert(self.path, "getting uri for note without path")
  return vim.uri_from_fname(tostring(self.path))
end

---@param opts { block: string|?, anchor: string|?, range: lsp.Range|obsidian.Range|? }|?
---@return lsp.Location
Note._location = function(self, opts)
  opts = opts or {}

  if (opts.range and opts.block) or (opts.range and opts.anchor) then
    error "can not pass both range and an block/anhor link to Note:_location()"
  end

  -- The full section the link points at: jumps land at its start and the
  -- whole range gets a blink highlight, like the Obsidian app.
  ---@type obsidian.Section|?
  local section
  if opts.block then
    local block_match = self:resolve_block(opts.block)
    section = block_match and block_match.section
  elseif opts.anchor then
    local anchor_match = self:resolve_anchor_link(opts.anchor)
    section = anchor_match and anchor_match.section
  end

  ---@type lsp.Range
  local range
  if opts.range then
    if opts.range.start_row then
      local obsidian_range = opts.range
      ---@cast obsidian_range obsidian.Range
      range = Range.to_lsp(obsidian_range)
    else
      local lsp_range = opts.range
      ---@cast lsp_range lsp.Range
      range = lsp_range
    end
  elseif section then
    range = Range.to_lsp(section.range)
  else
    range = {
      start = { line = 0, character = 0 },
      ["end"] = { line = 0, character = 0 },
    }
  end

  return {
    uri = self:uri(),
    range = range,
  }
end

--- Get a list of all of the different string that can identify this note via references,
--- including the ID, aliases, and filename.
---@param opts { lowercase: boolean|? }|?
---@return string[]
Note.reference_ids = function(self, opts)
  opts = opts or {}
  ---@type string[]
  local ref_ids = {
    tostring(self.id),
    self:display_name(), -- TODO: remove in the future
  }

  if self.path then
    table.insert(ref_ids, self.path.name)
    table.insert(ref_ids, self.path.stem)
  end

  vim.list_extend(ref_ids, self.aliases)

  if opts.lowercase then
    ref_ids = vim.tbl_map(string.lower, ref_ids)
  end

  return util.tbl_unique(ref_ids)
end

--- Get a list of all of the different paths that can identify this note
---@param opts? { urlencode: boolean|? }
---@return string[]
Note.get_reference_paths = function(self, opts)
  opts = opts or {}
  ---@type string[]
  local raw_refs = {}

  if self.path then
    table.insert(raw_refs, self.path.name)
    table.insert(raw_refs, self.path.stem)
  else
    return raw_refs
  end

  local relpath = self.path:vault_relative_path()
  if relpath then
    table.insert(raw_refs, relpath)
    local no_suffix_relpath = relpath:gsub(".md", "")
    table.insert(raw_refs, no_suffix_relpath)
  end

  raw_refs = util.tbl_unique(raw_refs)

  if opts.urlencode == true then
    local refs = {}

    for _, raw_ref in ipairs(raw_refs) do
      vim.list_extend(
        refs,
        util.tbl_unique {
          raw_ref,
          util.urlencode(raw_ref),
          util.urlencode(raw_ref, { keep_path_sep = true }),
        }
      )
    end
    return refs
  else
    return raw_refs
  end
end

--- Check if a note has a given alias.
---
---@param alias string
---
---@return boolean
Note.has_alias = function(self, alias)
  return vim.list_contains(self.aliases, alias)
end

--- Check if a note has a given tag.
---
---@param tag string
---
---@return boolean
Note.has_tag = function(self, tag)
  return vim.list_contains(self.tags, tag)
end

--- Add an alias to the note.
---
---@param alias string
---
---@return boolean added True if the alias was added, false if it was already present.
Note.add_alias = function(self, alias)
  if not self:has_alias(alias) then
    table.insert(self.aliases, alias)
    return true
  else
    return false
  end
end

--- Add a tag to the note.
---
---@param tag string
---
---@return boolean added True if the tag was added, false if it was already present.
Note.add_tag = function(self, tag)
  if not self:has_tag(tag) then
    table.insert(self.tags, tag)
    return true
  else
    return false
  end
end

--- Add or update a field in the frontmatter.
---
---@param key string
---@param value any
Note.add_field = function(self, key, value)
  if key == "id" or key == "aliases" or key == "tags" then
    error "Updating field '%s' this way is not allowed. Please update the corresponding attribute directly instead"
  end

  if not self.metadata then
    self.metadata = {}
  end

  self.metadata[key] = value
end

--- Get a field in the frontmatter.
---
---@param key string
---
---@return any result
Note.get_field = function(self, key)
  if key == "id" or key == "aliases" or key == "tags" then
    error "Getting field '%s' this way is not allowed. Please use the corresponding attribute directly instead"
  end

  if not self.metadata then
    return nil
  end

  return self.metadata[key]
end

--- Initialize a note from a file.
---
---@param path string|obsidian.Path
---@param opts obsidian.note.LoadOpts|?
---
---@return obsidian.Note
Note.from_file = function(path, opts)
  path = tostring(Path.new(path):resolve { strict = true })
  local file = assert(io.open(path, "r"), "failed to open file")
  local note = Note.from_lines(file:lines(), path, opts)
  file:close()
  return note
end

--- Initialize a note from a buffer.
---
---@param bufnr integer|?
---@param opts obsidian.note.LoadOpts|?
---
---@return obsidian.Note
Note.from_buffer = function(bufnr, opts)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local note = Note.from_lines(lines, path, opts)
  note.bufnr = bufnr

  ---@type obsidian.Note
  local cache_note = vim.b[bufnr].note
  if cache_note ~= nil then
    note = vim.tbl_extend("keep", note, cache_note)
    setmetatable(note, { __index = Note }) -- removes metatable for some reason ...
  end
  return note
end

--- Get the display name for note.
---
---@return string
Note.display_name = function(self)
  if self.title then
    return self.title
  elseif #self.aliases > 0 then
    return self.aliases[#self.aliases]
  end
  return tostring(self.id)
end

--- Initialize a note from an iterator of lines.
---
--- TODO: use vim.Iter here once the minimum Neovim runtime exposes that type.
---@param lines any
---@param path string|obsidian.Path|?
---@param opts obsidian.note.LoadOpts|?
---
---@return obsidian.Note note
---@return string[] warnings
Note.from_lines = function(lines, path, opts)
  opts = opts or {}
  path = path and Path.new(path):resolve()

  local max_lines = opts.max_lines or DEFAULT_MAX_LINES

  local contents = {}

  -- Iterate over lines in the file, collecting frontmatter and contents.
  local frontmatter_lines = {}
  local has_frontmatter, in_frontmatter = false, false
  local at_boundary
  local frontmatter_end_line = nil
  local line_idx = 0
  local next_line
  if type(lines) == "table" and vim.islist(lines) then
    next_line = function()
      line_idx = line_idx + 1
      return lines[line_idx]
    end
  else
    next_line = function()
      line_idx = line_idx + 1
      return lines()
    end
  end

  for line in next_line do
    line = util.rstrip_whitespace(line)

    if line_idx == 1 and Note._is_frontmatter_boundary(line) then
      has_frontmatter = true
      at_boundary = true
      in_frontmatter = true
    elseif in_frontmatter and Note._is_frontmatter_boundary(line) then
      at_boundary = true
      in_frontmatter = false
      frontmatter_end_line = line_idx
    else
      at_boundary = false
    end

    if in_frontmatter and not at_boundary then
      table.insert(frontmatter_lines, line)
    end

    -- Collect contents.
    table.insert(contents, line)

    -- Check if we can stop reading lines now.
    if line_idx > max_lines then
      break
    end
  end

  ---@type obsidian.Section[]|?, table<string, obsidian.note.Block>|?
  local sections, blocks
  if opts.collect_sections or opts.collect_anchor_links or opts.collect_blocks then
    sections, blocks = Section.parse(contents, {
      start_row = frontmatter_end_line or 0,
      collect_blocks = opts.collect_blocks,
    })
  end

  ---@type table<string, obsidian.note.HeaderAnchor>|?
  local anchor_links
  if opts.collect_anchor_links then
    anchor_links = {}
    ---@type table<obsidian.Section, obsidian.note.HeaderAnchor>
    local section_to_anchor = {}
    for _, section in ipairs(assert(sections, "sections must be parsed when collecting anchor links")) do
      if section.header then
        -- We collect up to two anchors for each header. One standalone, e.g. '#header1', and
        -- one with the parents, e.g. '#header1#header2'.
        local data = new_header_anchor(section, section.parent and section_to_anchor[section.parent], nil)
        section_to_anchor[section] = data
        anchor_links[section.anchor] = data

        if data.parent ~= nil then
          local nested_anchor = data.anchor
          ---@type obsidian.note.HeaderAnchor|?
          local parent = data.parent
          while parent ~= nil do
            nested_anchor = parent.anchor .. nested_anchor
            parent = parent.parent
          end
          anchor_links[nested_anchor] = new_header_anchor(section, data.parent, nested_anchor)
        end
      end
    end
  end

  local info = {}
  local warnings = {}

  -- Parse the frontmatter YAML.
  local metadata = {}
  if #frontmatter_lines > 0 then
    info, metadata, warnings = Frontmatter.parse(frontmatter_lines, path)
  end

  local id, aliases, tags = info.id, info.aliases, info.tags

  -- ID should default to the filename without the extension.
  if id == nil or (path and id == path.name) then
    id = path and path.stem
  end
  ---@cast id string

  local n = Note.new(id, aliases, tags, path)
  n.metadata = metadata
  n.has_frontmatter = has_frontmatter
  n.frontmatter_end_line = frontmatter_end_line
  n.contents = contents
  n.anchor_links = anchor_links
  n.blocks = blocks
  n.sections = sections
  -- TODO: reflect the warnings in `:Obsidian check`
  return n, warnings
end

--- Check if a line matches a frontmatter boundary.
---
---@param line string
---
---@return boolean
---
---@private
Note._is_frontmatter_boundary = function(line)
  return line:match "^%-%-%-+$" ~= nil
end

Note.frontmatter = require("obsidian.builtin").frontmatter

--- Get frontmatter lines that can be written to a buffer.
---
---@param current_lines string[]|?
---@return string[]
Note.frontmatter_lines = function(self, current_lines)
  local order
  local configured_order = Obsidian.opts.frontmatter.sort
  if configured_order ~= vim.NIL and (type(configured_order) == "table" or type(configured_order) == "function") then
    ---@cast configured_order string[]|fun(a: any, b: any): boolean
    order = configured_order
  end
  local syntax_ok
  local has_frontmatter = current_lines and not vim.tbl_isempty(current_lines)

  if has_frontmatter then
    local yaml_body_lines = vim.tbl_filter(function(line)
      return not Note._is_frontmatter_boundary(line)
    end, current_lines or {})
    -- Preserve the existing frontmatter's key order only when the user hasn't
    -- configured an explicit sort. Otherwise the user's `frontmatter.sort`
    -- would be silently overwritten by the parsed order on every save.
    local parse_result = { pcall(yaml.loads, table.concat(yaml_body_lines, "\n")) }
    syntax_ok = parse_result[1]
    local parsed_order = parse_result[3]
    if order == nil then
      order = parsed_order
    end
  end
  if syntax_ok or not has_frontmatter then -- if parse success or there's no frontmatter (and should insert)
    local frontmatter_func = Obsidian.opts.frontmatter.func
    ---@cast frontmatter_func -nil
    ---@diagnostic disable-next-line: param-type-mismatch
    local frontmatter_properties = frontmatter_func(self)
    if frontmatter_properties and not vim.tbl_isempty(frontmatter_properties) then
      return Frontmatter.dump(frontmatter_properties, order)
    else
      return current_lines or {}
    end
  else
    log.info "invalid yaml syntax in frontmatter"
    return current_lines or {}
  end
end

--- Update the frontmatter in a buffer for the note.
---
---@param bufnr integer|?
---
---@return boolean updated If the the frontmatter was updated.
Note.update_frontmatter = function(self, bufnr)
  if not self:should_save_frontmatter() then
    return false
  end

  return self:save_to_buffer { bufnr = bufnr }
end

--- Checks if the parameter note is in the blacklist of files which shouldn't have
--- frontmatter applied
---
--- @param note obsidian.Note The note
--- @return boolean true if so
local is_in_frontmatter_blacklist = function(note)
  local fname = note:fname()
  return (fname ~= nil and vim.list_contains(SKIP_UPDATING_FRONTMATTER, fname))
end

--- Determines whether a note's frontmatter is managed by obsidian.nvim.
---
---@return boolean
Note.should_save_frontmatter = function(self)
  -- Check if the note is a template.
  local templates_dir = api.templates_dir()
  if templates_dir ~= nil then
    templates_dir = templates_dir:resolve()
    for _, parent in ipairs(self.path:parents()) do
      if parent == templates_dir then
        return false
      end
    end
  end

  if ignore.is_ignored(tostring(self.path)) then
    return false
  end

  local enabled = Obsidian.opts.frontmatter.enabled

  if is_in_frontmatter_blacklist(self) then
    return false
  elseif type(enabled) == "boolean" then
    return enabled
  elseif type(enabled) == "function" then
    return enabled(self.path:vault_relative_path { strict = true })
  else
    return true
  end
end

--- Write the note to disk.
---
---@param opts? obsidian.note.NoteWriteOpts
---@return obsidian.Note
Note.write = function(self, opts)
  local Template = require "obsidian.templates"
  opts = vim.tbl_extend("keep", opts or {}, { check_buffers = true })

  local path = assert(self.path, "A path must be provided")
  path = Path.new(path)

  -- Fall back to the template carried by the note (set at Note.create).
  local template = opts.template ~= nil and opts.template or self.template
  local should_save_frontmatter = self:should_save_frontmatter()

  if not should_save_frontmatter and is_default_note_template(template) then
    template = nil
  end

  ---@type string
  local verb
  if path:is_file() then
    verb = "Updated"
  else
    verb = "Created"
    if template ~= nil then
      self = Template.clone_template {
        type = "clone_template",
        template_name = template,
        destination_path = path,
        templates_dir = api.templates_dir(),
        partial_note = self,
      }
    end
  end

  local frontmatter = nil
  if should_save_frontmatter and Obsidian.opts.frontmatter.func ~= nil then
    frontmatter = Obsidian.opts.frontmatter.func(self)
  end

  self:save {
    path = path,
    insert_frontmatter = should_save_frontmatter,
    frontmatter = frontmatter,
    update_content = opts.update_content,
    check_buffers = opts.check_buffers,
  }

  log.info("%s note '%s' at '%s'", verb, self.id, self.path:vault_relative_path(self.path) or self.path)

  return self
end

--- Save the note to a file.
--- In general this only updates the frontmatter and header, leaving the rest of the contents unchanged
--- unless you use the `update_content()` callback.
---
---@param opts? obsidian.note.NoteSaveOpts
Note.save = function(self, opts)
  opts = vim.tbl_extend("keep", opts or {}, { check_buffers = true })

  assert(self.path, "a path is required")

  local path = assert(opts.path or self.path, "no valid path for save")
  local save_path = Path.new(path):resolve()
  assert(save_path:parent()):mkdir { parents = true, exist_ok = true }

  -- Read contents from existing file or buffer, if there is one.
  -- TODO: check for open buffer?
  ---@type string[]
  local content = {}
  ---@type string[]
  local existing_frontmatter
  local has_trailing_newline = true -- Default to true for new files.

  if self.path:is_file() then
    -- Check if the file ends with a newline.
    local file = io.open(tostring(self.path), "rb")
    if file then
      local size = file:seek "end"
      if size and size > 0 then
        file:seek("end", -1)
        local last_char = file:read(1)
        has_trailing_newline = (last_char == "\n")
      end
      file:close()
    end

    existing_frontmatter = {}
    local in_frontmatter, at_boundary = false, false -- luacheck: ignore (false positive)
    local idx = 0
    for line in io.lines(tostring(self.path)) do
      idx = idx + 1
      if idx == 1 and Note._is_frontmatter_boundary(line) then
        at_boundary = true
        in_frontmatter = true
      elseif in_frontmatter and Note._is_frontmatter_boundary(line) then
        at_boundary = true
        in_frontmatter = false
      else
        at_boundary = false
      end

      if not in_frontmatter and not at_boundary then
        table.insert(content, line)
      else
        table.insert(existing_frontmatter, line)
      end
    end
    -- end)
    -- elseif self.title ~= nil then
    --   -- Add a header.
    --   table.insert(content, "# " .. self.title)
  end

  -- Pass content through callback.
  if opts.update_content then
    content = opts.update_content(content)
  end

  ---@type string[]
  local new_lines
  if opts.insert_frontmatter then
    -- Replace frontmatter.
    new_lines = util.flatten { self:frontmatter_lines(existing_frontmatter), content }
  else
    -- Use existing frontmatter.
    new_lines = util.flatten { existing_frontmatter, content }
  end

  local file_content = table.concat(new_lines, "\n")
  if has_trailing_newline then
    file_content = file_content .. "\n"
  end
  util.write_file(tostring(save_path), file_content)

  if opts.check_buffers then
    -- `:checktime <name>` parses {name} as a Vim regex, so paths with `[`,
    -- `*`, etc. raise E94. Pass the bufnr instead, iterating to cover
    -- every buffer loaded from this path.
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(bufnr) == save_path.filename then
        vim.cmd.checktime(bufnr)
      end
    end
  end
end

--- Write the note to a buffer.
---
---@param opts { bufnr: integer|?, template: string|? }|? Options.
---
--- Options:
---  - `bufnr`: Override the buffer to write to. Defaults to current buffer.
---  - `template`: The name of a template to use if the buffer is empty.
---
---@return boolean updated If the buffer was updated.
Note.write_to_buffer = function(self, opts)
  local Template = require "obsidian.templates"
  opts = opts or {}

  if opts.template and api.buffer_is_empty(opts.bufnr) then
    self = Template.insert_template {
      type = "insert_template",
      template_name = opts.template,
      templates_dir = api.templates_dir(),
      location = api.get_active_window_cursor_location(),
      partial_note = self,
    }
  end

  local should_save_frontmatter = self:should_save_frontmatter()

  return self:save_to_buffer { bufnr = opts.bufnr, insert_frontmatter = should_save_frontmatter }
end

--- Save the note to the buffer
---
---@param opts { bufnr: integer|?, insert_frontmatter: boolean|? }|? Options.
---
---@return boolean updated True if the buffer lines were updated, false otherwise.
Note.save_to_buffer = function(self, opts)
  opts = opts or {}

  local bufnr = opts.bufnr
  if not bufnr then
    bufnr = self.bufnr or 0
  end

  local frontmatter_end_line = self.frontmatter_end_line

  ---@type string[]
  local current_lines = {}
  if self.has_frontmatter then
    current_lines = vim.api.nvim_buf_get_lines(bufnr, 0, frontmatter_end_line or 0, false)
  end

  ---@type string[]
  local new_lines
  if opts.insert_frontmatter ~= false then
    new_lines = self:frontmatter_lines(current_lines)
  else
    new_lines = {}
  end

  if not vim.deep_equal(current_lines, new_lines) then
    vim.api.nvim_buf_set_lines(bufnr, 0, frontmatter_end_line and frontmatter_end_line or 0, false, new_lines)
    return true
  else
    return false
  end
end

--- Try to resolve an anchor link to a line number in the note's file.
---
---@param anchor_link string
---@return obsidian.note.HeaderAnchor|?
Note.resolve_anchor_link = function(self, anchor_link)
  anchor_link = util.standardize_anchor(anchor_link)

  if self.anchor_links ~= nil then
    return self.anchor_links[anchor_link]
  end

  assert(self.path, "'note.path' is not set")
  local n = Note.from_file(self.path, { collect_anchor_links = true })
  self.anchor_links = n.anchor_links
  return n:resolve_anchor_link(anchor_link)
end

--- Try to resolve a block identifier.
---
---@param block_id string
---
---@return obsidian.note.Block|?
Note.resolve_block = function(self, block_id)
  block_id = util.standardize_block(block_id)

  if self.blocks ~= nil then
    return self.blocks[block_id]
  end

  assert(self.path, "'note.path' is not set")
  local n = Note.from_file(self.path, { collect_blocks = true })
  self.blocks = n.blocks
  local blocks = self.blocks
  ---@cast blocks -nil
  return blocks[block_id]
end

--- Open a note in a buffer.
---
---@param opts { line: integer|?, col: integer|?, open_strategy: obsidian.config.OpenStrategy|?, sync: boolean|?, callback: fun(bufnr: integer)|? }|?
Note.open = function(self, opts)
  opts = opts or {}

  local function open_it()
    local open_cmd = api.get_open_strategy(opts.open_strategy and opts.open_strategy or Obsidian.opts.open_notes_in)
    local bufnr = api.open_note({
      filename = tostring(self.path),
      lnum = opts.line,
      col = opts.col and opts.col + 1,
    }, open_cmd)
    vim.b[bufnr].note = self
    if opts.callback then
      opts.callback(bufnr)
    end
  end

  if opts.sync then
    open_it()
  else
    vim.schedule(open_it)
  end
end

---@param opts { search: obsidian.SearchOpts?, anchor: string?, block: string?, timeout: integer?, dir: string|obsidian.Path?, refs: string[]? }?
---@return obsidian.BacklinkMatch[]
Note.backlinks = function(self, opts)
  local backlink_opts = opts or {}
  backlink_opts.dir = backlink_opts.dir or api.resolve_workspace_dir()
  return search.find_backlinks(self, backlink_opts)
end

---@param opts { search: obsidian.SearchOpts?, anchor: string?, block: string?, dir: string|obsidian.Path?, refs: string[]? }?
---@param callback fun(matches: obsidian.BacklinkMatch[])
Note.backlinks_async = function(self, opts, callback)
  local backlink_opts = opts or {}
  backlink_opts.dir = backlink_opts.dir or api.resolve_workspace_dir()
  return search.find_backlinks_async(self, callback, backlink_opts)
end

---@return obsidian.LinkMatch[]
Note.links = function(self)
  return search.find_links(self)
end

---@param path obsidian.Path vault-relative-path
---@param style obsidian.link.LinkFormat?
---@return string foramted_path
local function format_path(path, style)
  if style == "absolute" then
    return assert(path:vault_relative_path {})
  elseif style == "relative" then
    local base_dir = Obsidian.buf_dir or Obsidian.dir
    if base_dir == nil then
      return assert(path:vault_relative_path {})
    end

    local relpath =
      assert(util.relpath(tostring(base_dir), tostring(path)), "failed to resolve link path against current note")
    return relpath
  else
    return vim.fs.basename(tostring(path))
  end
end

--- Create a formatted markdown / wiki link for a note.
---
---@param opts obsidian.link.LinkCreationOpts?
---@return string
Note.format_link = function(self, opts)
  opts = opts or {}
  local label = opts.label or self:display_name()
  local link_style = opts.style or Obsidian.opts.link.style
  local link_format = opts.format or Obsidian.opts.link.format

  local new_opts = {
    path = format_path(self.path, link_format),
    label = label,
    anchor = opts.anchor,
    block = opts.block,
    style = link_style,
    format = link_format,
  }

  if link_style == "markdown" then
    return require("obsidian.builtin").markdown_link(new_opts)
  elseif link_style == "wiki" or link_style == nil then
    return require("obsidian.builtin").wiki_link(new_opts)
  elseif type(link_style) == "function" then
    return link_style(new_opts)
  else
    error(string.format("Invalid link style '%s'", link_style))
  end
end

-- HACK: make backlink search lazy before we have proper cache
local backlink_cache = {}

--- Return note status counts, like obsidian's status bar
---
---@param update_backlink boolean|?
---@param callback fun(status: { words: integer, chars: integer, properties: integer, backlinks: integer })|?
---@return { words: integer, chars: integer, properties: integer, backlinks: integer }?
Note.status = function(self, update_backlink, callback)
  local status = {}
  local wc = vim.fn.wordcount()
  status.words = wc.visual_words or wc.words
  status.chars = wc.visual_chars or wc.chars
  status.properties = vim.tbl_count(self:frontmatter()) -- TODO: should be zero if no frontmatter
  local path = tostring(self.path)

  local function finish(num_backlinks)
    status.backlinks = num_backlinks
    backlink_cache[path] = num_backlinks
    if callback then
      callback(status)
    else
      return status
    end
  end

  if self and (update_backlink or backlink_cache[path] == nil) then -- HACK:
    if callback then
      self:backlinks_async({}, function(matches)
        finish(#matches)
      end)
    else
      return finish(#self:backlinks {})
    end
  else
    return finish(backlink_cache[path] or 0)
  end
end

---@return string[]
Note.body_lines = function(self)
  if not self.has_frontmatter then
    return self.contents
  end
  local lines = {}
  for i = self.frontmatter_end_line + 1, #self.contents do
    lines[#lines + 1] = self.contents[i]
  end
  return lines
end

---@param choice obsidian.note.insert_text.SectionChoice
---@return { header?: string, level?: integer }
local function normalize_section_choice(choice)
  local norm = { header = nil, level = nil }

  if type(choice) == "string" then
    norm.header = choice
  elseif type(choice) == "number" then
    norm.level = choice
  elseif type(choice) == "table" then
    if vim.islist(choice) then
      norm.header = choice[1]
      norm.level = choice[2]
    else
      norm.header = choice.header
      norm.level = choice.level
    end
    assert(norm.header == nil or type(norm.header) == "string", "`section.header` must be string or nil")
    assert(norm.level == nil or type(norm.level) == "number", "`section.level` must be number or nil")
  elseif choice ~= nil then
    error("invalid `section`: " .. vim.inspect(choice))
  end

  return norm
end

---@param text string|string[] The text to insert into the note.
---@param opts obsidian.note.InsertTextOpts? The options for constraining where text can be inserted.
---@return integer text_idx where the text begins in the file (_including_ frontmatter) or `0` when insert is cancelled.
Note.insert_text = function(self, text, opts)
  local defaults = { padding_top = self.has_frontmatter }
  local overrides = { section = normalize_section_choice(opts and opts.section) }
  opts = vim.tbl_deep_extend("force", defaults, opts or {}, overrides)

  local text_idx = self.has_frontmatter and self.frontmatter_end_line or 0

  self:save(vim.tbl_extend("error", opts, {
    update_content = function(lines)
      local insert_idx, insert_top, insert_bot = text_insertion.resolve(lines, opts)
      if insert_idx == 0 then
        text_idx = 0
        return lines
      else
        text_idx = text_idx + insert_idx + #insert_top
        local top_lines = vim.list_slice(lines, 1, insert_idx - 1)
        local bot_lines = vim.list_slice(lines, insert_idx, #lines)
        local out = {}
        for _, group in ipairs { top_lines, insert_top, text, insert_bot, bot_lines } do
          if type(group) == "table" then
            for _, line in ipairs(group) do
              out[#out + 1] = line
            end
          else
            out[#out + 1] = group
          end
        end
        return out
      end
    end,
  }))

  return text_idx
end

---@param other obsidian.Note
---@return obsidian.Note
Note.merge = function(self, other)
  if not other.has_frontmatter or not other.frontmatter_end_line then
    return self
  end
  local frontmatter_lines = {}

  for i = 2, other.frontmatter_end_line - 1 do
    frontmatter_lines[#frontmatter_lines + 1] = other.contents[i]
  end

  local insert_frontmatter, insert_metadata = Frontmatter.parse(frontmatter_lines)

  for k, v in pairs(insert_frontmatter) do
    if k == "aliases" and type(v) == "table" then
      for _, alias in ipairs(v) do
        self:add_alias(alias)
      end
    elseif k == "tags" and type(v) == "table" then
      for _, tag in ipairs(v) do
        self:add_tag(tag)
      end
    end
  end

  local function listify(v)
    return vim.islist(v) and v or { v }
  end

  for k, v in pairs(insert_metadata) do
    if self.metadata[k] then
      local listified_v = listify(v)
      if not vim.islist(self.metadata[k]) then
        self.metadata[k] = listify(self.metadata[k])
      end
      vim.list_extend(self.metadata[k], listified_v)
    else
      self.metadata[k] = v
    end
  end

  self.has_frontmatter = true
  return self
end

---@class (exact) obsidian.note.LoadOpts
---@field max_lines integer|?
---@field collect_anchor_links boolean|?
---@field collect_blocks boolean|?
---@field collect_sections boolean|?

---@class (exact) obsidian.note.NoteCreationOpts
---@field notes_subdir string?
---@field note_id_func fun(title: string|?, path: obsidian.Path|?): string
---@field new_notes_location obsidian.config.NewNotesLocation

---@class (exact) obsidian.note.NoteOpts
---@field id string|? An ID to assign the note. It will be passed to global `note_id_func` unless `verbatim` is set to true
---@field title string|? Readable title for the note. Used as the alias and (when no `id` given) as the base for `note_id_func`.
---@field verbatim boolean|? whether to skip applying `note_id_func`
---@field dir string|obsidian.Path|? An optional directory to place the note in. Relative paths will be interpreted
---relative to the workspace / vault root.
---@field aliases string[]|? Aliases for the note
---@field tags string[]|?  Tags for this note
---@field template string|? Template name used to resolve template-specific path/customization (does NOT write the template; pass `template` to `note:write` for that).
---@field scope string|? Arbitrary note creation scope passed through to `opts.callbacks.create_note`; defaults to `"plain"`.

---@class (exact) obsidian.note.CreateCallbackOpts
---@field scope string Scope inherited from the `Note.create` opts, or `"plain"` when not set.

---@class (exact) obsidian.note.NoteSaveOpts
--- Specify a path to save to. Defaults to `self.path`.
---@field path? string|obsidian.Path
--- Whether to insert/update frontmatter. Defaults to `true`.
---@field insert_frontmatter? boolean
--- Override the frontmatter. Defaults to the result of `self:frontmatter()`.
---@field frontmatter? table
--- A function to update the contents of the note. This takes a list of lines representing the text to be written
--- excluding frontmatter, and returns the lines that will actually be written (again excluding frontmatter).
---@field update_content? fun(lines: string[]): string[]
--- Whether to call |checktime| on open buffers pointing to the written note. Defaults to true.
--- When enabled, Neovim will warn the user if changes would be lost and/or reload the updated file.
--- See `:help checktime` to learn more.
---@field check_buffers? boolean

---@class (exact) obsidian.note.NoteWriteOpts
--- Specify a path to save to. Defaults to `self.path`.
---@field path? string|obsidian.Path
--- The name of a template to use if the note file doesn't already exist.
---@field template? string
--- A function to update the contents of the note. This takes a list of lines representing the text to be written
--- excluding frontmatter, and returns the lines that will actually be written (again excluding frontmatter).
---@field update_content? fun(lines: string[]): string[]
--- Whether to call |checktime| on open buffers pointing to the written note. Defaults to true.
--- When enabled, Neovim will warn the user if changes would be lost and/or reload each buffer's content.
--- See `:help checktime` to learn more.
---@field check_buffers? boolean

---@class (exact) obsidian.note.InsertTextOpts: obsidian.note.NoteSaveOpts
--- Specifies the section to insert text under. When neither `header` nor `level` are provided, then the "preamble" will
--- be targeted (i.e. everything from the beginning of the file up to, but not including, the first heading).
--- Defaults to the preamble.
---@field section? obsidian.note.insert_text.SectionChoice
--- Decides what to do when the specified section is not found in the note. Defaults to `create`.
---@field on_section_missing? obsidian.note.insert_text.OnSectionMissing
--- Whether a blank line is inserted between frontmatter/top-of-file and the first heading of a note.
--- Defaults to the expression: `note.has_frontmatter`.
---@field padding_top? boolean
--- Specifies where the text should be inserted relative to the section or preamble. Defaults to `top`.
---@field placement? "top"|"bot"

--- Selects a section by preamble, header, level, or both.
--- - `nil`, `{ header = nil, level = nil }`, or `{ nil, nil }`: preamble.
--- - `string`, `{ header = string }`, or `{ string, nil }`: first matching header.
--- - `integer`, `{ level = integer }`, or `{ nil, integer }`: first matching level.
--- - `{ header = string, level = integer }` or `{ string, integer }`: first matching pair.
---@alias obsidian.note.insert_text.SectionChoice nil|string|integer|[string?, integer?]|{header: string?, level: integer?}

---@alias obsidian.note.insert_text.OnSectionMissing
---| "create" Create the missing section where text will be inserted under.
---| "error"  Force user to handle the missing section by raising an error.
---| "cancel" Silently abandon the insert operation altogether.

---@class obsidian.note.HeaderAnchor
---
---@field anchor string
---@field header string
---@field level integer
---@field line integer
---@field parent obsidian.note.HeaderAnchor|?
---@field section? obsidian.Section the full section this header begins.

---@class obsidian.note.Block
---
---@field id string
---@field line integer
---@field block string
---@field section? obsidian.Section the paragraph carrying the block identifier.

return Note
