local Path = require "obsidian.path"
local abc = require "obsidian.abc"
local yaml = require "obsidian.yaml"
local log = require "obsidian.log"
local util = require "obsidian.util"
local search = require "obsidian.search"
local iter = vim.iter
local enumerate = util.enumerate
local compat = require "obsidian.compat"
local api = require "obsidian.api"
local config = require "obsidian.config"

local SKIP_UPDATING_FRONTMATTER = { "README.md", "CONTRIBUTING.md", "CHANGELOG.md" }

local DEFAULT_MAX_LINES = 500

local CODE_BLOCK_PATTERN = "^%s*```[%w_-]*$"

--- @class obsidian.note.NoteCreationStrategy
--- @field notes_subdir string
--- @field note_id_func fun()
--- @field new_notes_location string

--- @class obsidian.note.NoteOpts
--- @field title string|? The note's title
--- @field id string|? An ID to assign the note. If not specified one will be generated.
--- @field dir string|obsidian.Path|? An optional directory to place the note in. Relative paths will be interpreted
--- relative to the workspace / vault root. If the directory doesn't exist it will
--- be created, regardless of the value of the `should_write` option.
--- @field aliases string[]|? Aliases for the note
--- @field tags string[]|?  Tags for this note
--- @field should_write boolean|? Don't write the note to disk
--- @field template string|? The name of the template

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

--- A class that represents a note within a vault.
---
---@toc_entry obsidian.Note
---
---@class obsidian.Note : obsidian.ABC
---
---@field id string
---@field aliases string[]
---@field title string|?
---@field tags string[]
---@field path obsidian.Path|?
---@field metadata table|?
---@field has_frontmatter boolean|?
---@field frontmatter_end_line integer|?
---@field contents string[]|?
---@field anchor_links table<string, obsidian.note.HeaderAnchor>|?
---@field blocks table<string, obsidian.note.Block>?
---@field alt_alias string|?
---@field bufnr integer|?
local Note = abc.new_class {
  __tostring = function(self)
    return string.format("Note('%s')", self.id)
  end,
}

Note.is_note_obj = function(note)
  if getmetatable(note) == Note.mt then
    return true
  else
    return false
  end
end

--- Generate a unique ID for a new note. This respects the user's `note_id_func` if configured,
--- otherwise falls back to generated a Zettelkasten style ID.
---
--- @param title? string
--- @param path? obsidian.Path
--- @param alt_id_func? (fun(title: string|?, path: obsidian.Path|?): string)
---@return string
local function new_note_id(title, path, alt_id_func)
  if alt_id_func ~= nil then
    local new_id = alt_id_func(title, path)
    if new_id == nil or string.len(new_id) == 0 then
      error(string.format("Your 'note_id_func' must return a non-empty string, got '%s'!", tostring(new_id)))
    end
    -- Remote '.md' suffix if it's there (we add that later).
    new_id = new_id:gsub("%.md$", "", 1)
    return new_id
  else
    return require("obsidian.builtin").zettel_id()
  end
end

--- Generate the file path for a new note given its ID, parent directory, and title.
--- This respects the user's `note_path_func` if configured, otherwise essentially falls back to
--- `note_opts.dir / (note_opts.id .. ".md")`.
---
--- @param title string|? The title for the note
--- @param id string The note ID
--- @param dir obsidian.Path The note path
---@return obsidian.Path
local function new_note_path(title, id, dir)
  ---@type obsidian.Path
  local path

  if Obsidian.opts.note_path_func ~= nil then
    path = Path.new(Obsidian.opts.note_path_func { id = id, dir = dir, title = title })
    -- Ensure path is either absolute or inside `opts.dir`.
    -- NOTE: `opts.dir` should always be absolute, but for extra safety we handle the case where
    -- it's not.
    if not path:is_absolute() and (dir:is_absolute() or not dir:is_parent_of(path)) then
      path = dir / path
    end
  else
    path = dir / tostring(id)
  end

  -- Ensure there is only one ".md" suffix. This might arise if `note_path_func`
  -- supplies an unusual implementation returning something like /bad/note/id.md.md.md
  while path.filename:match "%.md$" do
    path.filename = path.filename:gsub("%.md$", "")
  end

  return path:with_suffix(".md", true)
end

--- Selects the strategy to use when resolving the note title, id, and path
--- @param opts obsidian.note.NoteOpts The note creation options
--- @return obsidian.note.NoteCreationStrategy The strategy to use for creating the note
local function get_note_resolver_strategy(opts)
  --- @type obsidian.note.NoteCreationStrategy
  local default = {
    notes_subdir = Obsidian.opts.notes_subdir,
    note_id_func = Obsidian.opts.note_id_func,
    new_notes_location = Obsidian.opts.new_notes_location,
  }

  local template_strategy = require("obsidian.templates").load_template_customizations(opts.template or "")

  if template_strategy then
    default = vim.tbl_extend("force", default, template_strategy)
  end

  return default
end

--- Resolves the title, ID, and path for a new note.
---
---@param title string|?
---@param id string|?
---@param dir string|obsidian.Path|? The directory for the note
---@param strategy obsidian.note.NoteCreationStrategy Strategy for resolving note path and title
---@return string|?,string,obsidian.Path
local function resolve_title_id_path(title, id, dir, strategy)
  if title then
    title = vim.trim(title)
    if title == "" then
      title = nil
    end
  end

  if id then
    id = vim.trim(id)
    if id == "" then
      id = nil
    end
  end

  ---@param s string
  ---@param strict_paths_only boolean
  ---@return string|?, boolean, string|?
  local parse_as_path = function(s, strict_paths_only)
    local is_path = false
    ---@type string|?
    local parent

    if s:match "%.md" then
      -- Remove suffix.
      s = s:sub(1, s:len() - 3)
      is_path = true
    end

    -- Pull out any parent dirs from title.
    local parts = vim.split(s, "/")
    if #parts > 1 then
      s = parts[#parts]
      if not strict_paths_only then
        is_path = true
      end
      parent = table.concat(parts, "/", 1, #parts - 1)
    end

    if s == "" then
      return nil, is_path, parent
    else
      return s, is_path, parent
    end
  end

  local parent, _, title_is_path
  if id then
    id, _, parent = parse_as_path(id, false)
  elseif title then
    title, title_is_path, parent = parse_as_path(title, true)
    if title_is_path then
      id = title
    end
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
      strategy.new_notes_location == config.NewNotesLocation.current_dir
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
      if strategy.notes_subdir then
        base_dir = base_dir / strategy.notes_subdir
      end
    end
  end

  -- Make sure `base_dir` is absolute at this point.
  assert(base_dir:is_absolute(), ("failed to resolve note directory '%s'"):format(base_dir))

  -- Generate new ID if needed.
  if not id then
    id = new_note_id(title, base_dir, strategy.note_id_func)
  end

  dir = base_dir

  -- Generate path.
  local path = new_note_path(title, id, dir)

  return title, id, path
end

--- Creates a new note
---
--- @param opts obsidian.note.NoteOpts Options
--- @return obsidian.Note
Note.create = function(opts)
  local new_title, new_id, path = resolve_title_id_path(opts.title, opts.id, opts.dir, get_note_resolver_strategy(opts))
  opts = vim.tbl_extend("keep", opts, { aliases = {}, tags = {} })

  -- Add the title as an alias.
  --- @type string[]
  local aliases = opts.aliases
  if new_title ~= nil and new_title:len() > 0 and not vim.list_contains(aliases, new_title) then
    aliases[#aliases + 1] = new_title
  end

  local note = Note.new(new_id, aliases, opts.tags, path)

  if new_title then
    note.title = new_title
  end

  -- Ensure the parent directory exists.
  local parent = path:parent()
  assert(parent)
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
--- @return obsidian.Note
Note.new = function(id, aliases, tags, path)
  local self = Note.init()
  self.id = id
  self.aliases = aliases and aliases or {}
  self.tags = tags and tags or {}
  self.path = path and Path.new(path) or nil
  self.metadata = nil
  self.has_frontmatter = nil
  self.frontmatter_end_line = nil
  return self
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

--- Get a list of all of the different string that can identify this note via references,
--- including the ID, aliases, and filename.
---@param opts { lowercase: boolean|? }|?
---@return string[]
Note.reference_ids = function(self, opts)
  opts = opts or {}
  ---@type string[]
  local ref_ids = { tostring(self.id), self:display_name() }
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

---@class obsidian.note.LoadOpts
---@field max_lines integer|?
---@field load_contents boolean|?
---@field collect_anchor_links boolean|?
---@field collect_blocks boolean|?

--- Initialize a note from a file.
---
---@param path string|obsidian.Path
---@param opts obsidian.note.LoadOpts|?
---
---@return obsidian.Note
Note.from_file = function(path, opts)
  if path == nil then
    error "note path cannot be nil"
  end
  path = tostring(Path.new(path):resolve { strict = true })
  return Note.from_lines(io.lines(path), path, opts)
end

--- An async version of `.from_file()`, i.e. it needs to be called in an async context.
---
---@param path string|obsidian.Path
---@param opts obsidian.note.LoadOpts|?
---
---@return obsidian.Note
Note.from_file_async = function(path, opts)
  path = Path.new(path):resolve { strict = true }
  local f = io.open(tostring(path), "r")
  assert(f)
  local ok, res = pcall(Note.from_lines, f:lines "*l", path, opts)
  f:close()
  if ok then
    return res
  else
    error(res)
  end
end

--- Like `.from_file_async()` but also returns the contents of the file as a list of lines.
---
---@param path string|obsidian.Path
---@param opts obsidian.note.LoadOpts|?
---
---@return obsidian.Note,string[]
Note.from_file_with_contents_async = function(path, opts)
  opts = vim.tbl_extend("force", opts or {}, { load_contents = true })
  local note = Note.from_file_async(path, opts)
  assert(note.contents ~= nil)
  return note, note.contents
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
---@return obsidian.Note
Note.from_lines = function(lines, path, opts)
  opts = opts or {}
  path = Path.new(path):resolve()

  local max_lines = opts.max_lines or DEFAULT_MAX_LINES

  local id = nil
  local title = nil
  local aliases = {}
  local tags = {}

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
    assert(anchor_links)
    assert(anchor_stack)
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
  local has_frontmatter, in_frontmatter, at_boundary = false, false, false -- luacheck: ignore (false positive)
  local frontmatter_end_line = nil
  local in_code_block = false
  for line_idx, line in enumerate(lines) do
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
        if not title and header_match.level == 1 then
          title = header_match.header
        end

        -- Collect anchor link.
        if opts.collect_anchor_links then
          assert(anchor_links)
          assert(anchor_stack)
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
      or (title and not opts.load_contents and not opts.collect_anchor_links and not opts.collect_blocks)
    then
      break
    end
  end

  if title ~= nil then
    -- Remove references and links from title
    title = search.replace_refs(title)
  end

  -- Parse the frontmatter YAML.
  local metadata = nil
  if #frontmatter_lines > 0 then
    local frontmatter = table.concat(frontmatter_lines, "\n")
    local ok, data = pcall(yaml.loads, frontmatter)
    if type(data) ~= "table" then
      data = {}
    end
    if ok then
      ---@diagnostic disable-next-line: param-type-mismatch
      for k, v in pairs(data) do
        if k == "id" then
          if type(v) == "string" then
            id = v
          else
            log.warn("Invalid 'id' in frontmatter for " .. tostring(path))
          end
        elseif k == "aliases" then
          if type(v) == "table" then
            for alias in iter(v) do
              if type(alias) == "string" then
                table.insert(aliases, alias)
              else
                log.warn(
                  "Invalid alias value found in frontmatter for "
                    .. path
                    .. ". Expected string, found "
                    .. type(alias)
                    .. "."
                )
              end
            end
          elseif type(v) == "string" then
            table.insert(aliases, v)
          else
            log.warn("Invalid 'aliases' in frontmatter for " .. tostring(path))
          end
        elseif k == "tags" then
          if type(v) == "table" then
            for tag in iter(v) do
              if type(tag) == "string" then
                table.insert(tags, tag)
              else
                log.warn(
                  "Invalid tag value found in frontmatter for "
                    .. tostring(path)
                    .. ". Expected string, found "
                    .. type(tag)
                    .. "."
                )
              end
            end
          elseif type(v) == "string" then
            tags = vim.split(v, " ")
          else
            log.warn("Invalid 'tags' in frontmatter for '%s'", path)
          end
        else
          if metadata == nil then
            metadata = {}
          end
          metadata[k] = v
        end
      end
    end
  end

  -- ID should default to the filename without the extension.
  if id == nil or id == path.name then
    id = path.stem
  end
  assert(id)

  local n = Note.new(id, aliases, tags, path)
  n.title = title
  n.metadata = metadata
  n.has_frontmatter = has_frontmatter
  n.frontmatter_end_line = frontmatter_end_line
  n.contents = contents
  n.anchor_links = anchor_links
  n.blocks = blocks
  return n
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
Note.frontmatter = function(self)
  local out = { id = self.id, aliases = self.aliases, tags = self.tags }
  if self.metadata ~= nil and not vim.tbl_isempty(self.metadata) then
    for k, v in pairs(self.metadata) do
      out[k] = v
    end
  end
  return out
end

--- Get frontmatter lines that can be written to a buffer.
---
---@param eol boolean|?
---@param frontmatter table|?
---
---@return string[]
Note.frontmatter_lines = function(self, eol, frontmatter)
  local new_lines = { "---" }

  local frontmatter_ = frontmatter and frontmatter or self:frontmatter()
  if vim.tbl_isempty(frontmatter_) then
    return {}
  end

  for line in
    iter(yaml.dumps_lines(frontmatter_, function(a, b)
      local a_idx = nil
      local b_idx = nil
      for i, k in ipairs { "id", "aliases", "tags" } do
        if a == k then
          a_idx = i
        end
        if b == k then
          b_idx = i
        end
      end
      if a_idx ~= nil and b_idx ~= nil then
        return a_idx < b_idx
      elseif a_idx ~= nil then
        return true
      elseif b_idx ~= nil then
        return false
      else
        return a < b
      end
    end))
  do
    table.insert(new_lines, line)
  end

  table.insert(new_lines, "---")
  if not self.has_frontmatter then
    -- Make sure there's an empty line between end of the frontmatter and the contents.
    table.insert(new_lines, "")
  end

  if eol then
    return vim.tbl_map(function(l)
      return l .. "\n"
    end, new_lines)
  else
    return new_lines
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

  local frontmatter = nil
  if Obsidian.opts.note_frontmatter_func ~= nil then
    frontmatter = Obsidian.opts.note_frontmatter_func(self)
  end
  return self:save_to_buffer { bufnr = bufnr, frontmatter = frontmatter }
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

  if is_in_frontmatter_blacklist(self) then
    return false
  elseif type(Obsidian.opts.disable_frontmatter) == "boolean" then
    return not Obsidian.opts.disable_frontmatter
  elseif type(Obsidian.opts.disable_frontmatter) == "function" then
    return not Obsidian.opts.disable_frontmatter(self.path:vault_relative_path { strict = true })
  else
    return true
  end
end

--- Write the note to disk.
---
---@param opts { path: string|obsidian.Path, template: string|?, update_content: (fun(lines: string[]): string[])|? }|? Options.
---
--- Options:
---  - `template`: The name of a template to use if the note file doesn't already exist.
---  - `update_content`: A function to update the contents of the note. This takes a list of lines
---    representing the text to be written excluding frontmatter, and returns the lines that will
---    actually be written (again excluding frontmatter).
---
---@return obsidian.Note
Note.write = function(self, opts)
  local Template = require "obsidian.templates"
  opts = opts or {}

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
  if Obsidian.opts.note_frontmatter_func ~= nil then
    frontmatter = Obsidian.opts.note_frontmatter_func(self)
  end

  self:save {
    path = path,
    insert_frontmatter = self:should_save_frontmatter(),
    frontmatter = frontmatter,
    update_content = opts.update_content,
  }

  log.info("%s note '%s' at '%s'", verb, self.id, self.path:vault_relative_path(self.path) or self.path)

  return self
end

--- Save the note to a file.
--- In general this only updates the frontmatter and header, leaving the rest of the contents unchanged
--- unless you use the `update_content()` callback.
---
---@param opts { path: string|obsidian.Path|?, insert_frontmatter: boolean|?, frontmatter: table|?, update_content: (fun(lines: string[]): string[])|? }|? Options.
---
--- Options:
---  - `path`: Specify a path to save to. Defaults to `self.path`.
---  - `insert_frontmatter`: Whether to insert/update frontmatter. Defaults to `true`.
---  - `frontmatter`: Override the frontmatter. Defaults to the result of `self:frontmatter()`.
---  - `update_content`: A function to update the contents of the note. This takes a list of lines
---    representing the text to be written excluding frontmatter, and returns the lines that will
---    actually be written (again excluding frontmatter).
Note.save = function(self, opts)
  opts = opts or {}

  if self.path == nil then
    error "a path is required"
  end

  local save_path = Path.new(assert(opts.path or self.path)):resolve()
  assert(save_path:parent()):mkdir { parents = true, exist_ok = true }

  -- Read contents from existing file or buffer, if there is one.
  -- TODO: check for open buffer?
  ---@type string[]
  local content = {}
  ---@type string[]
  local existing_frontmatter = {}
  if self.path ~= nil and self.path:is_file() then
    -- with(open(tostring(self.path)), function(reader)
    local in_frontmatter, at_boundary = false, false -- luacheck: ignore (false positive)
    for idx, line in enumerate(io.lines(tostring(self.path))) do
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
  elseif self.title ~= nil then
    -- Add a header.
    table.insert(content, "# " .. self.title)
  end

  -- Pass content through callback.
  if opts.update_content then
    content = opts.update_content(content)
  end

  ---@type string[]
  local new_lines
  if opts.insert_frontmatter ~= false then
    -- Replace frontmatter.
    new_lines = compat.flatten { self:frontmatter_lines(false, opts.frontmatter), content }
  else
    -- Use existing frontmatter.
    new_lines = compat.flatten { existing_frontmatter, content }
  end

  util.write_file(tostring(save_path), table.concat(new_lines, "\n"))
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

  local frontmatter = nil
  local should_save_frontmatter = self:should_save_frontmatter()
  if should_save_frontmatter and Obsidian.opts.note_frontmatter_func ~= nil then
    frontmatter = Obsidian.opts.note_frontmatter_func(self)
  end

  return self:save_to_buffer {
    bufnr = opts.bufnr,
    insert_frontmatter = should_save_frontmatter,
    frontmatter = frontmatter,
  }
end

--- Save the note to the buffer
---
---@param opts { bufnr: integer|?, insert_frontmatter: boolean|?, frontmatter: table|? }|? Options.
---
---@return boolean updated True if the buffer lines were updated, false otherwise.
Note.save_to_buffer = function(self, opts)
  opts = opts or {}

  local bufnr = opts.bufnr
  if not bufnr then
    bufnr = self.bufnr or 0
  end

  local cur_buf_note = Note.from_buffer(bufnr)

  ---@type string[]
  local new_lines
  if opts.insert_frontmatter ~= false then
    new_lines = self:frontmatter_lines(nil, opts.frontmatter)
  else
    new_lines = {}
  end

  if api.buffer_is_empty(bufnr) and self.title ~= nil then
    table.insert(new_lines, "# " .. self.title)
  end

  ---@type string[]
  local cur_lines = {}
  if cur_buf_note.frontmatter_end_line ~= nil then
    cur_lines = vim.api.nvim_buf_get_lines(bufnr, 0, cur_buf_note.frontmatter_end_line, false)
  end

  if not vim.deep_equal(cur_lines, new_lines) then
    vim.api.nvim_buf_set_lines(
      bufnr,
      0,
      cur_buf_note.frontmatter_end_line and cur_buf_note.frontmatter_end_line or 0,
      false,
      new_lines
    )
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

return Note
