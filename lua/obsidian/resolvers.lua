local log = require "obsidian.log"
local Path = require "obsidian.path"
local picker = require "obsidian.picker"
local date = require "obsidian.date"
local uri = require "obsidian.uri"
local api = require "obsidian.api"

local M = {}

--- Maximum display characters for note preview titles.
local MAX_TITLE_CHARS = 80

--- Matches a code-fence marker line, mirroring the section parser.
local CODE_FENCE_PATTERN = "^```[%w_-]*$"

---@class obsidian.resolver.AttachmentCtx
---@field bufnr integer
---@field source string|?
---@field intent string

---@class obsidian.resolver.AttachmentResult
---@field path string Local filepath, file URI, or URL accepted by `obsidian.attachment.add`.

---@class obsidian.resolver.DateCtx
---@field intent string
---@field cadence string|?
---@field offset_start integer|?
---@field offset_end integer|?
---@field default_timestamp integer|?

---@class obsidian.resolver.DateResult
---@field timestamp integer Unix timestamp.
---@field precision string|?
---@field label string|?
---@field offset integer|?

---@class obsidian.resolver.HintsCtx
---@field bufnr integer
---@field note obsidian.Note
---@field range lsp.Range|?

---@alias obsidian.resolver.HintsResult lsp.InlayHint[]
---@alias obsidian.resolver.Hints fun(ctx: obsidian.resolver.HintsCtx, done: fun(result: obsidian.resolver.HintsResult|?, err: string|?))

--- Context for the `note_preview` resolver.
---
---@class obsidian.resolver.NotePreviewCtx
---@field scope string Where the preview is displayed, e.g. `"lsp.completion"` (completion documentation).
---@field note obsidian.Note The note being previewed.
---@field label string|? The resolved link text to show at the top, if any.
---@field anchor obsidian.note.HeaderAnchor|? Heading anchor being linked to, if any.
---@field block obsidian.note.Block|? Block being linked to, if any.

--- Markdown documentation for a note preview.
---@alias obsidian.resolver.NotePreviewResult string

---@alias obsidian.Resolver fun(ctx: table, done: fun(result: any, err: string|?))

---@type table<string, obsidian.Resolver>
M.builtin = {}

---@param src string
---@param done fun(result: obsidian.resolver.AttachmentResult|?, err: string|?)
local function resolve_attachment_source(src, done)
  src = vim.trim(src)
  if src == "" then
    done(nil)
    return
  end

  local is_uri, scheme = uri.is_uri(src)
  if is_uri and scheme then
    if scheme == "http" or scheme == "https" then
      done { path = src }
    elseif scheme == "file" then
      done { path = vim.uri_to_fname(src) }
    else
      done(nil, "Unknown URI format")
    end
    return
  end

  local expanded = vim.fn.expand(src)
  ---@cast expanded string
  local path = vim.fs.normalize(vim.fn.fnamemodify(expanded, ":p"))
  local stat = vim.uv.fs_stat(path)
  if stat and stat.type == "directory" then
    picker.find_files {
      dir = path,
      include_non_markdown = true,
      callback = function(paths)
        if paths[1] then
          done { path = paths[1] }
        end
      end,
    }
  else
    done { path = path }
  end
end

---@type obsidian.Resolver
M.builtin.attachment = function(ctx, done)
  if ctx.source ~= nil and vim.trim(ctx.source) ~= "" then
    resolve_attachment_source(ctx.source, done)
    return
  end

  vim.ui.input({ prompt = "Url or filepath", completion = "file" }, function(input)
    if not input then
      done(nil)
      return
    end
    resolve_attachment_source(input, done)
  end)
end

---@param datetime integer
---@return obsidian.Path
local function daily_note_path(datetime)
  local path = Path.new(api.resolve_workspace_dir())
  local options = Obsidian.opts

  if options.daily_notes.folder ~= nil then
    path = path / options.daily_notes.folder
  elseif options.notes_subdir ~= nil then
    path = path / options.notes_subdir
  end

  local date_format = assert(options.daily_notes.date_format, "daily notes date_format is required")
  local daily_path = path / (tostring(date.format(datetime, date_format, options.daily_notes.start_of_week)) .. ".md")
  ---@cast daily_path obsidian.Path
  return daily_path
end

---@type obsidian.Resolver
M.builtin.date = function(ctx, done)
  if ctx.offset_start == nil or ctx.offset_end == nil then
    done {
      timestamp = ctx.default_timestamp or os.time(),
      precision = "day",
    }
    return
  end

  ---@type obsidian.PickerEntry[]
  local dailies = {}
  local options = Obsidian.opts
  for offset = ctx.offset_end, ctx.offset_start, -1 do
    local datetime = os.time() + (offset * 3600 * 24)
    local daily_path = daily_note_path(datetime)
    local label = tostring(
      date.format(datetime, options.daily_notes.alias_format or "%A %B %-d, %Y", options.daily_notes.start_of_week)
    )
    if offset == 0 then
      label = label .. " @today"
    elseif offset == -1 then
      label = label .. " @yesterday"
    elseif offset == 1 then
      label = label .. " @tomorrow"
    end
    if not daily_path:is_file() then
      label = label .. " ➡️ create"
    end
    dailies[#dailies + 1] = {
      user_data = {
        offset = offset,
        timestamp = datetime,
        label = label,
      },
      text = label,
      filename = tostring(daily_path),
    }
  end

  picker.select(dailies, {
    prompt = "Dailies",
    preview_item = function(entry)
      if vim.uv.fs_stat(entry.filename) then
        return picker.preview_path(entry.filename)
      end

      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].bufhidden = "wipe"
      vim.bo[buf].filetype = "markdown"
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Select to create this daily note." })
      return { buf = buf }
    end,
  }, function(entries)
    if not entries or #entries == 0 then
      done(nil)
      return
    end
    local entry = entries[1]
    ---@cast entry { user_data: { timestamp: integer, label: string, offset: integer } }
    done {
      timestamp = entry.user_data.timestamp,
      precision = "day",
      label = entry.user_data.label,
      offset = entry.user_data.offset,
    }
  end)
end

---@type obsidian.Resolver
M.builtin.hints = function(ctx, done)
  done(require "obsidian.lsp.inlay_hints.link"(ctx.note, ctx.range))
end

--- Truncate a string to `max_chars` display characters, appending an ellipsis when truncated.
---
---@param text string
---@param max_chars integer
---@return string
local function truncate(text, max_chars)
  if vim.fn.strchars(text) > max_chars then
    return vim.fn.strcharpart(text, 0, max_chars - 1) .. "…"
  end
  return text
end

--- Iterate the meaningful body lines of a note (frontmatter, blank lines, and
--- `%%` / `<!-- -->` comments are skipped). Code-fence markers and fenced
--- content are yielded like normal lines; callers decide how to treat them.
---
---@param note obsidian.Note
---@return fun(): string|?
local function iter_body_lines(note)
  local contents = note.contents
  if contents == nil then
    return function() end
  end

  local i = (note.has_frontmatter and note.frontmatter_end_line or 0) + 1

  if note.frontmatter_end_line == nil and contents[1] and contents[1]:match "^%-%-%-+$" then
    -- Contents may be lazily loaded without frontmatter metadata (e.g. notes
    -- built from the cache), in which case the frontmatter is still part of
    -- `contents`. Skip it so its comments are never mistaken for content.
    i = 2
    while i <= #contents and not (contents[i] or ""):match "^%-%-%-+$" do
      i = i + 1
    end
    i = i + 1
  end

  local in_obsidian_comment = false
  local in_html_comment = false

  return function()
    while i <= #contents do
      local line = vim.trim(contents[i] or "")
      i = i + 1
      if in_obsidian_comment then
        if line:find("%%", 1, true) then
          in_obsidian_comment = false
        end
      elseif in_html_comment then
        if line:find("-->", 1, true) then
          in_html_comment = false
        end
      elseif line ~= "" and vim.startswith(line, "%%") then
        -- Obsidian comment; only opens a block when not closed on the same line.
        if not line:find("%%", 3, true) then
          in_obsidian_comment = true
        end
      elseif line ~= "" and vim.startswith(line, "<!--") then
        -- HTML comment; only opens a block when not closed on the same line.
        if not line:find("-->", 5, true) then
          in_html_comment = true
        end
      elseif line ~= "" then
        return line
      end
    end
    return nil
  end
end

--- Extract a human-readable title for a note from already-loaded state.
---
--- Priority: frontmatter `title` metadata, then the first H1 heading, which is
--- read from the note's sections when available (notes built from the cache
--- reconstruct them from the cached headings) and otherwise searched in
--- already-loaded contents. Returns `nil` when the note has no semantic title.
---
---@param note obsidian.Note
---@return string|?
local function note_title(note)
  local metadata_title = note.metadata and note.metadata.title or nil
  if type(metadata_title) == "string" then
    metadata_title = vim.trim(metadata_title)
    if metadata_title ~= "" then
      return truncate(metadata_title, MAX_TITLE_CHARS)
    end
  elseif type(metadata_title) == "number" then
    return truncate(tostring(metadata_title), MAX_TITLE_CHARS)
  end

  for _, section in ipairs(note.sections or {}) do
    if section.level == 1 and section.header then
      return truncate(section.header, MAX_TITLE_CHARS)
    end
  end

  -- Notes loaded from a plain file scan have their contents in memory but no
  -- parsed sections; search those. Lazily loaded contents are never read here,
  -- so resolving a preview never touches the disk.
  if rawget(note, "contents") ~= nil then
    local in_code_block = false
    for line in iter_body_lines(note) do
      if line:match(CODE_FENCE_PATTERN) then
        in_code_block = not in_code_block
      elseif not in_code_block then
        local h1 = line:match "^#%s+(.-)%s*$"
        if h1 and h1 ~= "" then
          return truncate(h1, MAX_TITLE_CHARS)
        end
      end
    end
  end

  return nil
end

--- Render the default note preview.
---
---@param ctx obsidian.resolver.NotePreviewCtx
---@return string
M.default_note_preview = function(ctx)
  local title
  if ctx.scope == "lsp.completion" then
    title = note_title(ctx.note)
  end
  return ctx.note:display_info {
    label = ctx.label,
    anchor = ctx.anchor,
    block = ctx.block,
    title = title,
  }
end

---@type obsidian.Resolver
M.builtin.note_preview = function(ctx, done)
  done(M.default_note_preview(ctx))
end

---@param name string
---@param ctx table|?
---@param done fun(result: any, err: string|?)
M.resolve = function(name, ctx, done)
  ctx = ctx or {}
  local resolver = Obsidian.opts.resolvers and Obsidian.opts.resolvers[name] or nil
  resolver = resolver or M.builtin[name]
  if not resolver then
    local err = "No resolver registered for '" .. name .. "'"
    log.err(err)
    done(nil, err)
    return
  end

  local called = false
  local function once(result, err)
    if called then
      return
    end
    called = true
    if err then
      log.err(err)
    end
    done(result, err)
  end

  local ok, err = pcall(resolver, ctx, once)
  if not ok then
    once(nil, tostring(err))
  end
end

return M
