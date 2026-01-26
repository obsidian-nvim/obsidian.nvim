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
local iter = vim.iter
local compat = require "obsidian.compat"
local api = require "obsidian.api"
local config = require "obsidian.config"
local Frontmatter = require "obsidian.frontmatter"
local search = require "obsidian.search"

local SKIP_UPDATING_FRONTMATTER = { "README.md", "CONTRIBUTING.md", "CHANGELOG.md" }

local DEFAULT_MAX_LINES = 500

local CODE_BLOCK_PATTERN = "^%s*```[%w_-]*$"

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
---@field path obsidian.Path|?
---@field metadata table
---@field has_frontmatter boolean|?
---@field frontmatter_end_line integer|?
---@field contents string[]|?
---@field anchor_links table<string, obsidian.note.HeaderAnchor>|?
---@field blocks table<string, obsidian.note.Block>?
---@field alt_alias string|?
---@field bufnr integer|?
local Note = {}

local load_contents = function(note)
  local contents = {}
  local path = tostring(rawget(note, "path"))
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

  local resolve_template = require("obsidian.templates").resolve_template
  local success, template_path = pcall(resolve_template, opts.template, api.templates_dir())

  if not success then
    return ret
  end

  local stem = template_path.stem:lower()

  -- Check if the configuration has a custom key for this template
  for key, cfg in pairs(Obsidian.opts.templates.customizations) do
    if key:lower() == stem then
      ret = {
        notes_subdir = cfg.notes_subdir,
        note_id_func = cfg.note_id_func,
        new_notes_location = "notes_subdir",
      }
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
---@return string title
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
    base_dir = Obsidian.dir / parent
  elseif dir ~= nil then
    base_dir = Path.new(dir)
    if not base_dir:is_absolute() then
      base_dir = Obsidian.dir / base_dir
    else
      base_dir = base_dir:resolve()
    end
  else
    local bufpath = Path.buffer(0):resolve()
    if
      creation_opts.new_notes_location == "current_dir"
      -- note is actually in the workspace.
      and Obsidian.dir:is_parent_of(bufpath)
      -- note is not in dailies folder
      and (
        Obsidian.opts.daily_notes.folder == nil
        or not (Obsidian.dir / Obsidian.opts.daily_notes.folder):is_parent_of(bufpath)
      )
    then
      base_dir = Obsidian.buf_dir or assert(bufpath:parent())
    else
      base_dir = Obsidian.dir
      if creation_opts.notes_subdir then
        base_dir = base_dir / creation_opts.notes_subdir
      end
    end
  end

  -- Make sure `base_dir` is absolute at this point.
  assert(base_dir:is_absolute(), ("failed to resolve note directory '%s'"):format(base_dir))

  local title = id

  -- Apply id transform
  if not (opts.verbatim and id) then
    id = generate_id(id, base_dir, creation_opts.note_id_func)
  end

  dir = base_dir

  -- Generate path.
  local path = Note._generate_path(id, dir)

  return id, path, title
end

--- Creates a new note
---
--- @param opts obsidian.note.NoteOpts
--- @return obsidian.Note
Note.create = function(opts)
  local new_id, path, title = Note._resolve_id_path(opts)
  opts = vim.tbl_extend("keep", opts, { aliases = {}, tags = {} })

  -- Add the title as an alias.
  --- @type string[]
  local aliases = opts.aliases
  local note = Note.new(new_id, aliases, opts.tags, path, title)

  -- Ensure the parent directory exists.
  local parent = path:parent()
  assert(parent, "failed to get parent in note creation")
  parent:mkdir { parents = true, exist_ok = true }

  -- Write to disk.
  if opts.should_write then
    note:write { template = opts.template }
  end

  return note
end

--- Instantiates a new Note object
---
--- Keep in mind that you have to call `note:save(...)` to create/update the note on disk.
---
--- @param id string|number
--- @param aliases string[]
--- @param tags string[]
--- @param path string|obsidian.Path|?
--- @param title string
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

---@param opts { block: string|?, anchor: string|?, range: lsp.Range|? }|?-- TODO: vim.Range in the future
---@return lsp.Location
Note._location = function(self, opts)
  opts = opts or {}

  if (opts.range and opts.block) or (opts.range and opts.anchor) then
    error "can not pass both range and an block/anhor link to Note:_location()"
  end

  ---@type integer|?, obsidian.note.Block|?, obsidian.note.HeaderAnchor|?
  local line = 0
  if opts.block then
    local block_match = self:resolve_block(opts.block)
    if block_match then
      line = block_match.line - 1
    end
  elseif opts.anchor then
    local anchor_match = self:resolve_anchor_link(opts.anchor)
    if anchor_match then
      line = anchor_match.line - 1
    end
  end

  local range = opts.range
    or {
      start = { line = line, character = 0 },
      ["end"] = { line = line, character = 0 },
    }

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
  assert(path, "note path cannot be nil")
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
  local note = Note.from_lines(iter(lines), path, opts)
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
---@param lines fun(): string|? | Iter
---@param path string|obsidian.Path
---@param opts obsidian.note.LoadOpts|?
---
---@return obsidian.Note note
---@return string[] warnings
Note.from_lines = function(lines, path, opts)
  opts = opts or {}
  path = Path.new(path):resolve()

  local max_lines = opts.max_lines or DEFAULT_MAX_LINES

  -- local id = nil
  -- local title
  -- local aliases = {}
  -- local tags = {}

  ---@type string[]|?
  local contents
  if opts.load_contents then
    contents = {}
  end

  ---@type table<string, obsidian.note.HeaderAnchor>|?
  local anchor_links
  ---@type obsidian.note.HeaderAnchor[]|?
  local anchor_stack
  if opts.collect_anchor_links then
    anchor_links = {}
    anchor_stack = {}
  end

  ---@type table<string, obsidian.note.Block>|?
  local blocks
  if opts.collect_blocks then
    blocks = {}
  end

  ---@param anchor_data obsidian.note.HeaderAnchor
  ---@return obsidian.note.HeaderAnchor|?
  local function get_parent_anchor(anchor_data)
    assert(anchor_links and anchor_stack, "failed to collect anchor")
    for i = #anchor_stack, 1, -1 do
      local parent = anchor_stack[i]
      if parent.level < anchor_data.level then
        return parent
      end
    end
  end

  ---@param anchor string
  ---@param data obsidian.note.HeaderAnchor|?
  local function format_nested_anchor(anchor, data)
    local out = anchor
    if not data then
      return out
    end

    local parent = data.parent
    while parent ~= nil do
      out = parent.anchor .. out
      data = get_parent_anchor(parent)
      if data then
        parent = data.parent
      else
        parent = nil
      end
    end

    return out
  end

  -- Iterate over lines in the file, collecting frontmatter and parsing the title.
  local frontmatter_lines = {}
  local has_frontmatter, in_frontmatter, at_boundary = false, false, false
  local frontmatter_end_line = nil
  local in_code_block = false
  for line_idx, line in vim.iter(lines):enumerate() do
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

    if string.match(line, CODE_BLOCK_PATTERN) then
      in_code_block = not in_code_block
    end

    if in_frontmatter and not at_boundary then
      table.insert(frontmatter_lines, line)
    elseif not in_frontmatter and not at_boundary and not in_code_block then
      -- Check for title/header and collect anchor link.
      local header_match = util.parse_header(line)
      if header_match then
        -- Collect anchor link.
        if opts.collect_anchor_links then
          assert(anchor_links and anchor_stack, "failed to collect anchor")
          -- We collect up to two anchor for each header. One standalone, e.g. '#header1', and
          -- one with the parents, e.g. '#header1#header2'.
          -- This is our standalone one:
          ---@type obsidian.note.HeaderAnchor
          local data = {
            anchor = header_match.anchor,
            line = line_idx,
            header = header_match.header,
            level = header_match.level,
          }
          data.parent = get_parent_anchor(data)

          anchor_links[header_match.anchor] = data
          table.insert(anchor_stack, data)

          -- Now if there's a parent we collect the nested version. All of the data will be the same
          -- except the anchor key.
          if data.parent ~= nil then
            local nested_anchor = format_nested_anchor(header_match.anchor, data)
            anchor_links[nested_anchor] = vim.tbl_extend("force", data, { anchor = nested_anchor })
          end
        end
      end

      -- Check for block.
      if opts.collect_blocks then
        local block = util.parse_block(line)
        if block then
          blocks[block] = { id = block, line = line_idx, block = line }
        end
      end
    end

    -- Collect contents.
    if contents ~= nil then
      table.insert(contents, line)
    end

    -- Check if we can stop reading lines now.
    if
      line_idx > max_lines
      -- or (title and not opts.load_contents and not opts.collect_anchor_links and not opts.collect_blocks) -- TODO: always false
    then
      break
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
  if id == nil or id == path.name then
    id = path.stem
  end
  assert(id, "failed to find a valid id for note")

  local n = Note.new(id, aliases, tags, path)
  n.metadata = metadata
  n.has_frontmatter = has_frontmatter
  n.frontmatter_end_line = frontmatter_end_line
  n.contents = contents
  n.anchor_links = anchor_links
  n.blocks = blocks
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
  return line:match "^---+$" ~= nil
end

--- Get the frontmatter table to save.
---
---@return table
Note.frontmatter = require("obsidian.builtin").frontmatter

--- Get frontmatter lines that can be written to a buffer.
---
---@param current_lines string[]
---@return string[]
Note.frontmatter_lines = function(self, current_lines)
  local order
  if Obsidian.opts.frontmatter.sort then
    order = Obsidian.opts.frontmatter.sort
  end
  local syntax_ok
  local has_frontmatter = current_lines and not vim.tbl_isempty(current_lines)

  if has_frontmatter then
    local yaml_body_lines = vim.tbl_filter(function(line)
      return not Note._is_frontmatter_boundary(line)
    end, current_lines)
    syntax_ok, _, order = pcall(yaml.loads, table.concat(yaml_body_lines, "\n"))
  end
  if syntax_ok or not has_frontmatter then -- if parse success or there's no frontmatter (and should insert)
    ---@diagnostic disable-next-line: param-type-mismatch
    return Frontmatter.dump(Obsidian.opts.frontmatter.func(self), order)
  else
    log.info "invalid yaml syntax in frontmatter"
    return current_lines
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

  if not self.has_frontmatter then
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

  local enabled = Obsidian.opts.frontmatter.enabled

  if is_in_frontmatter_blacklist(self) then
    return false
  elseif not self.has_frontmatter then
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

  ---@type string
  local verb
  if path:is_file() then
    verb = "Updated"
  else
    verb = "Created"
    if opts.template ~= nil then
      self = Template.clone_template {
        type = "clone_template",
        template_name = opts.template,
        destination_path = path,
        template_opts = Obsidian.opts.templates,
        templates_dir = assert(api.templates_dir(), "Templates folder is not defined or does not exist"),
        partial_note = self,
      }
    end
  end

  local frontmatter = nil
  if Obsidian.opts.frontmatter.func ~= nil then
    frontmatter = Obsidian.opts.frontmatter.func(self)
  end

  self:save {
    path = path,
    insert_frontmatter = self:should_save_frontmatter(),
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
    for idx, line in vim.iter(io.lines(tostring(self.path))):enumerate() do
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
    new_lines = compat.flatten { self:frontmatter_lines(existing_frontmatter), content }
  else
    -- Use existing frontmatter.
    new_lines = compat.flatten { existing_frontmatter, content }
  end

  local file_content = table.concat(new_lines, "\n")
  if has_trailing_newline then
    file_content = file_content .. "\n"
  end
  util.write_file(tostring(save_path), file_content)

  if opts.check_buffers then
    -- `vim.fn.bufnr` returns the **max** bufnr loaded from the same path.
    if vim.fn.bufnr(save_path.filename) ~= -1 then
      -- But we want to call |checktime| on **all** buffers loaded from the path.
      vim.cmd.checktime(save_path.filename)
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
      template_opts = Obsidian.opts.templates,
      templates_dir = assert(api.templates_dir(), "Templates folder is not defined or does not exist"),
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
  return self.blocks[block_id]
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
      col = opts.col,
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

---@param opts { search: obsidian.SearchOpts, anchor: string, block: string, timeout: integer, dir: string|obsidian.Path }
---@return obsidian.BacklinkMatch
Note.backlinks = function(self, opts)
  opts.dir = opts.dir or api.find_workspace(self.path).path
  return search.find_backlinks(self, opts)
end

---@return obsidian.LinkMatch
Note.links = function(self)
  return search.find_links(self)
end

--- Create a formatted markdown / wiki link for a note.
---
---@param opts { label: string|?, link_style: obsidian.config.LinkStyle|?, id: string|integer|?, anchor: obsidian.note.HeaderAnchor|?, block: obsidian.note.Block|? }|? Options.
---@return string
Note.format_link = function(self, opts)
  opts = opts or {}
  local rel_path = assert(self.path:vault_relative_path { strict = true }, "note with no path")
  local label = opts.label or self:display_name()
  local note_id = opts.id or self.id
  local link_style = opts.link_style or Obsidian.opts.preferred_link_style

  local new_opts = {
    path = rel_path,
    label = label,
    id = note_id,
    anchor = opts.anchor,
    block = opts.block,
  }

  if link_style == config.LinkStyle.markdown then
    return Obsidian.opts.markdown_link_func(new_opts)
  elseif link_style == config.LinkStyle.wiki or link_style == nil then
    return Obsidian.opts.wiki_link_func(new_opts)
  else
    error(string.format("Invalid link style '%s'", link_style))
  end
end

-- HACK: make backlink search lazy before we have proper cache
local backlink_cache = {}

--- Return note status counts, like obsidian's status bar
---
---@param update_backlink boolean|?
---@return { words: integer, chars: integer, properties: integer, backlinks: integer }?
Note.status = function(self, update_backlink)
  local status = {}
  local wc = vim.fn.wordcount()
  status.words = wc.visual_words or wc.words
  status.chars = wc.visual_chars or wc.chars
  status.properties = vim.tbl_count(self:frontmatter()) -- TODO: should be zero if no frontmatter
  local path = tostring(self.path)
  if self and (update_backlink or backlink_cache[path] == nil) then -- HACK:
    local num_backlinks = #self:backlinks {}
    status.backlinks = num_backlinks
    backlink_cache[path] = num_backlinks
  else
    status.backlinks = backlink_cache[path] or 0
  end
  return status
end

---@class (exact) obsidian.note.LoadOpts
---@field max_lines integer|?
---@field load_contents boolean|?
---@field collect_anchor_links boolean|?
---@field collect_blocks boolean|?

---@class (exact) obsidian.note.NoteCreationOpts
---@field notes_subdir string
---@field note_id_func fun()
---@field new_notes_location obsidian.config.NewNotesLocation

---@class (exact) obsidian.note.NoteOpts
---@field id string|? An ID to assign the note. It will be passed to global `note_id_func` unless `verbatim` is set to true
---@field verbatim boolean|? whether to skip applying `note_id_func`
---@field dir string|obsidian.Path|? An optional directory to place the note in. Relative paths will be interpreted
---relative to the workspace / vault root. If the directory doesn't exist it will
---be created, regardless of the value of the `should_write` option.
---@field aliases string[]|? Aliases for the note
---@field tags string[]|?  Tags for this note
---@field should_write boolean|? Don't write the note to disk
---@field template string|? The name of the template

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

---@class obsidian.note.HeaderAnchor
---
---@field anchor string
---@field header string
---@field level integer
---@field line integer
---@field parent obsidian.note.HeaderAnchor|?

---@class obsidian.note.Block
---
---@field id string
---@field line integer
---@field block string

return Note
