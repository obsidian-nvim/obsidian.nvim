local BufferDocument = require "obsidian.document"
local Document = require "obsidian.parse.document"
local Path = require "obsidian.path"
local Range = require "obsidian.range"
local api = require "obsidian.api"
local header = require "obsidian.parse.header"
local log = require "obsidian.log"
local parse_block_id = require "obsidian.parse.block_id"
local parse_tags = require "obsidian.parse.tags"
local refs = require "obsidian.parse.refs"
local search = require "obsidian.search"
local tags = require "obsidian.tag"

local has_nvim_0_12 = (vim.fn.has "nvim-0.12.0" == 1)

local M = {}

---@class obsidian.lsp.RenameTarget
---@field kind "note"|"block"|"heading"|"footnote"|"tag"
---@field bufnr integer
---@field range lsp.Range -- text replaced in bufnr (utf-8 byte columns)
---@field placeholder string
---@field ref obsidian.parse.Ref|? -- kind == "note": the link under the cursor
---@field id string|? -- block id without "^", footnote name
---@field header string|? -- heading text; nil when coming from `[[#Heading]]`
---@field anchor string|? -- normalized "#anchor"

---@param row integer
---@param start_col integer
---@param end_col integer
---@return lsp.Range
local function range(row, start_col, end_col)
  return {
    start = { line = row, character = start_col },
    ["end"] = { line = row, character = end_col },
  }
end

--- Buffer and position of a rename request, defaulting to the current buffer and cursor.
---@param params { textDocument: lsp.TextDocumentIdentifier|?, position: lsp.Position|? }|?
---@return integer bufnr
---@return lsp.Position position
M.resolve_params = function(params)
  params = params or {}
  local bufnr = params.textDocument and vim.uri_to_bufnr(params.textDocument.uri) or vim.api.nvim_get_current_buf()
  local position = params.position
  if not position then
    local cursor = vim.api.nvim_win_get_cursor(0)
    position = { line = cursor[1] - 1, character = cursor[2] }
  end
  return bufnr, position
end

--- The `#`-separated fragment components of a wiki/markdown ref, with absolute
--- 0-indexed byte columns. A block component is the one starting with `^`.
---@param ref obsidian.parse.Ref
---@return { text: string, col: integer }[]
M.fragment_components = function(ref)
  local raw = ref.raw
  local from, to
  if ref.kind == "wiki" then
    from = raw:find("#", ref.embed and 4 or 3, true)
    local pipe = from and raw:find("|", from, true)
    to = (pipe or #raw - 1) - 1
  else
    -- The markdown label may contain `#`, so start after `](`.
    local paren = raw:find("](", 1, true)
    from = paren and raw:find("#", paren + 2, true)
    to = #raw - 1
  end

  local out = {}
  if not from then
    return out
  end
  local pos = from + 1
  while pos <= to + 1 do
    local nxt = raw:find("#", pos, true)
    if not nxt or nxt > to then
      nxt = to + 1
    end
    if nxt > pos then
      out[#out + 1] = { text = raw:sub(pos, nxt - 1), col = ref.range.start_col + pos - 1 }
    end
    pos = nxt + 1
  end
  return out
end

---@param ref obsidian.parse.Ref
---@param bufnr integer
---@param row integer
---@return obsidian.lsp.RenameTarget|?
local function link_target(ref, bufnr, row)
  if ref.kind == "footnote" then
    return {
      kind = "footnote",
      bufnr = bufnr,
      id = ref.target,
      placeholder = ref.target,
      range = range(row, ref.range.start_col + 2, ref.range.end_col - 1),
    }
  end

  if ref.kind ~= "wiki" and ref.kind ~= "markdown" then
    return nil
  end

  local last = M.fragment_components(ref)
  last = last[#last]

  if ref.target == "" and ref.block and last then
    return {
      kind = "block",
      bufnr = bufnr,
      id = ref.block,
      placeholder = ref.block,
      range = range(row, last.col + 1, last.col + #last.text),
    }
  end

  if ref.target == "" and ref.anchor and last then
    return {
      kind = "heading",
      bufnr = bufnr,
      anchor = header.normalize_anchor(vim.uri_decode(last.text)),
      placeholder = last.text,
      range = range(row, last.col, last.col + #last.text),
    }
  end

  if ref.target ~= "" then
    local open = ref.kind == "wiki" and (ref.embed and 3 or 2) or select(2, ref.raw:find("](", 1, true))
    local s = open and ref.raw:find(ref.target, open + 1, true)
    if not s then
      return nil
    end
    local col = ref.range.start_col + s - 1
    return {
      kind = "note",
      bufnr = bufnr,
      ref = ref,
      placeholder = ref.target,
      range = range(row, col, col + #ref.target),
    }
  end
end

--- Find what a rename request at `position` acts on.
---@param bufnr integer
---@param position lsp.Position
---@return obsidian.lsp.RenameTarget|?
M.target_at = function(bufnr, position)
  local row, cur_col = position.line, position.character
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  local document = BufferDocument.get(bufnr)

  local _, kind, _, ref = api.cursor_link(bufnr, position)
  if kind and ref then
    return link_target(ref, bufnr, row)
  end

  -- Inline `#tag` and `tags:` entries of the frontmatter.
  for _, occurrence in ipairs(tags.extract(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { document = document })) do
    local r = occurrence.range
    if r.start_row == row and r.start_col <= cur_col and cur_col < r.end_col then
      return {
        kind = "tag",
        bufnr = bufnr,
        id = occurrence.tag,
        placeholder = occurrence.tag,
        range = range(row, occurrence.source == "inline" and r.start_col + 1 or r.start_col, r.end_col),
      }
    end
  end

  for _, block in ipairs(parse_block_id.extract(line, { row = row, lexical = true })) do
    if
      block.range.start_col <= cur_col
      and cur_col < block.range.end_col
      and not document:intersects(block.range, Document.BODY_EXCLUSIONS)
    then
      return {
        kind = "block",
        bufnr = bufnr,
        id = block.raw:sub(2),
        placeholder = block.raw:sub(2),
        range = range(row, block.range.start_col + 1, block.range.end_col),
      }
    end
  end

  local parsed = header.parse(line)
  local first_byte = line:find "%S"
  if parsed and first_byte then
    local marker = Range.new(row, first_byte - 1, row, first_byte)
    if not document:intersects(marker, Document.BODY_EXCLUSIONS) then
      local s, e = line:find(parsed.header, parsed.level + 1, true)
      return {
        kind = "heading",
        bufnr = bufnr,
        header = parsed.header,
        anchor = parsed.anchor,
        placeholder = parsed.header,
        range = range(row, s - 1, e),
      }
    end
  end
end

---@param path string|obsidian.Path
---@return string
local function path_key(path)
  return vim.fs.normalize(tostring(Path.new(path):resolve()))
end

---@alias obsidian.lsp.FileEdits table<string, lsp.TextEdit[]>

---@param file_edits obsidian.lsp.FileEdits
---@param path string
---@param row integer
---@param start_col integer
---@param end_col integer
---@param text string
local function add_edit(file_edits, path, row, start_col, end_col, text)
  file_edits[path] = file_edits[path] or {}
  table.insert(file_edits[path], { range = range(row, start_col, end_col), newText = text })
end

--- One `WorkspaceEdit`: identical ranges deduplicated, edits sorted last to first.
---@param file_edits obsidian.lsp.FileEdits
---@return lsp.WorkspaceEdit|?
local function to_workspace_edit(file_edits)
  local changes = {}
  for path, edits in pairs(file_edits) do
    local seen, unique = {}, {}
    for _, edit in ipairs(edits) do
      local r = edit.range
      local key = ("%d:%d:%d:%d"):format(r.start.line, r.start.character, r["end"].line, r["end"].character)
      if not seen[key] then
        seen[key] = true
        unique[#unique + 1] = edit
      end
    end
    table.sort(unique, function(a, b)
      if a.range.start.line == b.range.start.line then
        return a.range.start.character > b.range.start.character
      end
      return a.range.start.line > b.range.start.line
    end)
    changes[#changes + 1] = {
      textDocument = { uri = vim.uri_from_fname(path), version = has_nvim_0_12 and vim.NIL or nil },
      edits = unique,
    }
  end
  table.sort(changes, function(a, b)
    return a.textDocument.uri < b.textDocument.uri
  end)
  return #changes > 0 and { documentChanges = changes } or nil
end

---@class obsidian.lsp.CollectedRef
---@field path string
---@field row integer
---@field ref obsidian.parse.Ref

--- Every ref pointing at the note of `bufnr`: `[[#...]]` refs of the buffer itself
--- plus every link to the note found in the vault. The vault search already drops
--- code and comments.
---@param bufnr integer
---@param callback fun(collected: obsidian.lsp.CollectedRef[])
local function collect_refs(bufnr, callback)
  local note = api.current_note(bufnr)
  if not note then
    log.err "Current buffer is not a note inside the vault"
    return callback {}
  end

  ---@type obsidian.lsp.CollectedRef[]
  local out = {}
  local own = path_key(vim.api.nvim_buf_get_name(bufnr))
  local document = BufferDocument.get(bufnr)
  for row, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    for _, ref in ipairs(refs.extract(line, { row = row - 1, lexical = true })) do
      local origin = Range.new(row - 1, ref.range.start_col, row - 1, ref.range.start_col + 1)
      if
        ref.target == ""
        and not document:intersects(origin, Document.INLINE_EXCLUSIONS)
        and not document:intersects(ref.range, Document.COMMENTS)
      then
        out[#out + 1] = { path = own, row = row - 1, ref = ref }
      end
    end
  end

  search.find_backlinks_async(note, function(matches)
    for _, match in ipairs(matches) do
      for _, ref in ipairs(refs.extract(match.text, { row = match.line - 1, lexical = true })) do
        if ref.range.start_col + (ref.embed and 1 or 0) == match.start then
          out[#out + 1] = { path = path_key(match.path), row = match.line - 1, ref = ref }
        end
      end
    end
    callback(out)
  end, { dir = api.resolve_workspace_dir(note.path) })
end

--- Block ids defined in the buffer, outside code and comments.
---@param bufnr integer
---@return { id: string, row: integer, start_col: integer, end_col: integer }[]
local function block_definitions(bufnr)
  local document = BufferDocument.get(bufnr)
  local out = {}
  for row, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    for _, block in ipairs(parse_block_id.extract(line, { row = row - 1, lexical = true })) do
      if not document:intersects(block.range, Document.BODY_EXCLUSIONS) then
        out[#out + 1] = {
          id = block.raw:sub(2),
          row = row - 1,
          start_col = block.range.start_col + 1,
          end_col = block.range.end_col,
        }
      end
    end
  end
  return out
end

--- Rewrite a block id in its definition and in every reference to it.
---@param target obsidian.lsp.RenameTarget
---@param new_name string
---@param callback fun(edit: lsp.WorkspaceEdit|?)
M.build_block_edit = function(target, new_name, callback)
  local new_id = (vim.trim(new_name):gsub("^%^", ""))
  if not new_id:match "^%w[%w-]*$" then
    log.err(('Invalid block id "%s": use letters, digits and "-"'):format(new_id))
    return callback(nil)
  end
  if new_id == target.id then
    log.info "Identical name"
    return callback(nil)
  end

  local definition
  for _, def in ipairs(block_definitions(target.bufnr)) do
    if def.id == target.id then
      definition = def
    elseif def.id == new_id then
      log.err(('Block id "^%s" already exists in this note'):format(new_id))
      return callback(nil)
    end
  end
  if not definition then
    log.err(('Block "^%s" not found in this note'):format(target.id))
    return callback(nil)
  end

  collect_refs(target.bufnr, function(collected)
    ---@type obsidian.lsp.FileEdits
    local file_edits = {}
    add_edit(
      file_edits,
      path_key(vim.api.nvim_buf_get_name(target.bufnr)),
      definition.row,
      definition.start_col,
      definition.end_col,
      new_id
    )
    for _, item in ipairs(collected) do
      if item.ref.block == target.id then
        for _, comp in ipairs(M.fragment_components(item.ref)) do
          if comp.text == "^" .. target.id then
            add_edit(file_edits, item.path, item.row, comp.col + 1, comp.col + #comp.text, new_id)
          end
        end
      end
    end
    callback(to_workspace_edit(file_edits))
  end)
end

--- ATX headings of the buffer, outside code and comments.
---@param bufnr integer
---@return { row: integer, text: string, anchor: string, start_col: integer, end_col: integer }[]
local function headings(bufnr)
  local document = BufferDocument.get(bufnr)
  local out = {}
  for row, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    local parsed = header.parse(line)
    local first_byte = line:find "%S"
    if parsed and first_byte then
      local marker = Range.new(row - 1, first_byte - 1, row - 1, first_byte)
      if not document:intersects(marker, Document.BODY_EXCLUSIONS) then
        local s, e = line:find(parsed.header, parsed.level + 1, true)
        out[#out + 1] = { row = row - 1, text = parsed.header, anchor = parsed.anchor, start_col = s - 1, end_col = e }
      end
    end
  end
  return out
end

--- A heading component of a link keeps the style it was written in: raw text,
--- URL-encoded, or slug.
---@param component string
---@param old_text string
---@param new_text string
---@return string
local function restyle(component, old_text, new_text)
  if component == old_text then
    return new_text
  end
  if vim.uri_decode(component) ~= component then
    return require("obsidian.uri").encode(new_text)
  end
  if component == header.normalize_anchor(component):sub(2) then
    return header.to_anchor(new_text):sub(2)
  end
  return new_text
end

--- Rewrite a heading's text and every link component that names it. Refused when
--- the heading is not unique in its note, because a link cannot say which one it means.
---@param target obsidian.lsp.RenameTarget
---@param new_name string
---@param callback fun(edit: lsp.WorkspaceEdit|?)
M.build_heading_edit = function(target, new_name, callback)
  local new_text = vim.trim(new_name)
  if new_text == "" or new_text:find("\n", 1, true) or vim.startswith(new_text, "#") then
    log.err(('Invalid heading "%s"'):format(new_text))
    return callback(nil)
  end

  local all = headings(target.bufnr)
  local same = vim.tbl_filter(function(h)
    return h.anchor == target.anchor
  end, all)
  local definition = same[1]
  if target.header then
    -- Cursor on the heading line itself.
    definition = vim.iter(all):find(function(h)
      return h.row == target.range.start.line
    end)
  end
  if not definition then
    log.err(('Heading "%s" not found in this note'):format(target.placeholder))
    return callback(nil)
  end
  if #same > 1 then
    log.err(('Heading "%s" is not unique in this note'):format(definition.text))
    return callback(nil)
  end
  if new_text == definition.text then
    log.info "Identical name"
    return callback(nil)
  end
  local new_anchor = header.to_anchor(new_text)
  for _, other in ipairs(all) do
    if other ~= definition and other.anchor == new_anchor then
      log.err(('Heading "%s" already exists in this note'):format(new_text))
      return callback(nil)
    end
  end

  collect_refs(target.bufnr, function(collected)
    ---@type obsidian.lsp.FileEdits
    local file_edits = {}
    add_edit(
      file_edits,
      path_key(vim.api.nvim_buf_get_name(target.bufnr)),
      definition.row,
      definition.start_col,
      definition.end_col,
      new_text
    )
    for _, item in ipairs(collected) do
      for _, comp in ipairs(M.fragment_components(item.ref)) do
        if
          not vim.startswith(comp.text, "^") and header.normalize_anchor(vim.uri_decode(comp.text)) == target.anchor
        then
          local replacement = restyle(comp.text, definition.text, new_text)
          add_edit(file_edits, item.path, item.row, comp.col, comp.col + #comp.text, replacement)
        end
      end
    end
    callback(to_workspace_edit(file_edits))
  end)
end

--- Rewrite a footnote name in its definition and every reference. Footnotes are
--- scoped to their note, so only the buffer is touched.
---@param target obsidian.lsp.RenameTarget
---@param new_name string
---@param callback fun(edit: lsp.WorkspaceEdit|?)
M.build_footnote_edit = function(target, new_name, callback)
  local footnotes = require "obsidian.footnotes"
  local new_id = (vim.trim(new_name):gsub("^%^", ""))
  if not new_id:match "^[^%]%[%s%^]+$" then
    log.err(('Invalid footnote name "%s"'):format(new_id))
    return callback(nil)
  end
  if new_id == target.id then
    log.info "Identical name"
    return callback(nil)
  end
  if #footnotes.find_refs(target.bufnr, new_id) > 0 then
    log.err(('Footnote "[^%s]" already exists in this note'):format(new_id))
    return callback(nil)
  end

  ---@type obsidian.lsp.FileEdits
  local file_edits = {}
  local path = path_key(vim.api.nvim_buf_get_name(target.bufnr))
  for _, occurrence in ipairs(footnotes.find_refs(target.bufnr, target.id)) do
    add_edit(file_edits, path, occurrence.lnum - 1, occurrence.start_col + 2, occurrence.end_col - 1, new_id)
  end
  callback(to_workspace_edit(file_edits))
end

--- Rewrite a tag, and every tag below it (`a` also renames `a/b`), in the inline
--- text and the frontmatter of the whole vault. Renaming onto an existing tag
--- merges the two.
---@param target obsidian.lsp.RenameTarget
---@param new_name string
---@param callback fun(edit: lsp.WorkspaceEdit|?)
M.build_tag_edit = function(target, new_name, callback)
  local new_tag = (vim.trim(new_name):gsub("^#", ""))
  local parsed = parse_tags.extract("#" .. new_tag, { lexical = true })[1]
  if not parsed or parsed.tag ~= new_tag or new_tag:find("//", 1, true) or new_tag:match "/$" then
    log.err(('Invalid tag "%s": use letters, digits, "_", "-" and "/"'):format(new_tag))
    return callback(nil)
  end
  if new_tag == target.id then
    log.info "Identical name"
    return callback(nil)
  end

  local dir = api.resolve_workspace_dir(vim.api.nvim_buf_get_name(target.bufnr))
  search.find_tags_async(target.id, function(locations)
    ---@type obsidian.lsp.FileEdits
    local file_edits = {}
    for _, location in ipairs(locations) do
      local r = location.range
      -- Inline ranges include the `#`, frontmatter ranges do not.
      local start_col = location.text:sub(r.start_col + 1, r.start_col + 1) == "#" and r.start_col + 1 or r.start_col
      add_edit(file_edits, path_key(location.path), r.start_row, start_col, start_col + #target.id, new_tag)
    end
    callback(to_workspace_edit(file_edits))
  end, { dir = dir, match = "subtree" })
end

return M
