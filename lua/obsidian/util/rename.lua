local BufferDocument = require "obsidian.document"
local Document = require "obsidian.parse.document"
local Path = require "obsidian.path"
local Range = require "obsidian.range"
local api = require "obsidian.api"
local log = require "obsidian.log"
local refs = require "obsidian.parse.refs"
local search = require "obsidian.search"

local has_nvim_0_12 = (vim.fn.has "nvim-0.12.0" == 1)

---@alias obsidian.rename.FileEdits table<string, lsp.TextEdit[]>

---@class obsidian.rename.CollectedRef
---@field path string
---@field row integer
---@field ref obsidian.parse.Ref

---@class obsidian.rename.Opts
---@field apply? boolean Apply the workspace edit. Defaults to true.
---@field offset_encoding? "utf-8"|"utf-16"|"utf-32" Offset encoding used when applying. Defaults to `"utf-8"`.

---@alias obsidian.rename.Callback fun(err: string|?, edit: lsp.WorkspaceEdit|?)

--- Helpers shared by the rename of every element (tag, heading, block id, footnote).
local M = {}

---@param row integer
---@param start_col integer
---@param end_col integer
---@return lsp.Range
M.range = function(row, start_col, end_col)
  return {
    start = { line = row, character = start_col },
    ["end"] = { line = row, character = end_col },
  }
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

---@param path string|obsidian.Path
---@return string
M.path_key = function(path)
  return vim.fs.normalize(tostring(Path.new(path):resolve()))
end

---@param file_edits obsidian.rename.FileEdits
---@param path string
---@param row integer
---@param start_col integer
---@param end_col integer
---@param text string
M.add_edit = function(file_edits, path, row, start_col, end_col, text)
  file_edits[path] = file_edits[path] or {}
  table.insert(file_edits[path], { range = M.range(row, start_col, end_col), newText = text })
end

--- One `WorkspaceEdit`: identical ranges deduplicated, edits sorted last to first.
---@param file_edits obsidian.rename.FileEdits
---@return lsp.WorkspaceEdit|?
M.to_workspace_edit = function(file_edits)
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

--- Every ref pointing at the note of `bufnr`: `[[#...]]` refs of the buffer itself
--- plus every link to the note found in the vault. The vault search already drops
--- code and comments.
---@param bufnr integer
---@param callback fun(collected: obsidian.rename.CollectedRef[])
M.collect_refs = function(bufnr, callback)
  local note = api.current_note(bufnr)
  if not note then
    log.err "Current buffer is not a note inside the vault"
    return callback {}
  end

  ---@type obsidian.rename.CollectedRef[]
  local out = {}
  local own = M.path_key(vim.api.nvim_buf_get_name(bufnr))
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
          out[#out + 1] = { path = M.path_key(match.path), row = match.line - 1, ref = ref }
        end
      end
    end
    callback(out)
  end, { dir = api.resolve_workspace_dir(note.path) })
end

--- `(opts, callback)` of a rename: `opts` may be the callback itself. Returns nil when
--- `apply = false` comes without a callback, since the edit would be lost.
---@param opts obsidian.rename.Opts|obsidian.rename.Callback|?
---@param callback obsidian.rename.Callback|?
---@return any opts The rename opts; `any` so that callers can assign it to their own subclass of `obsidian.rename.Opts`.
---@return obsidian.rename.Callback|? callback
M.args = function(opts, callback)
  if type(opts) == "function" then
    return {}, opts
  end
  opts = opts or {}
  if opts.apply == false and not callback then
    log.err "callback is required when rename opts.apply is false"
    return nil, nil
  end
  return opts, callback
end

---@param err string
---@param callback obsidian.rename.Callback|?
M.fail = function(err, callback)
  log.err(err)
  if callback then
    callback(err, nil)
  end
end

--- Apply `edit` unless `opts.apply == false`, then hand it to `callback`.
---@param opts obsidian.rename.Opts
---@param callback obsidian.rename.Callback|?
---@param edit lsp.WorkspaceEdit|?
M.finish = function(opts, callback, edit)
  if opts.apply ~= false and edit then
    vim.lsp.util.apply_workspace_edit(edit, opts.offset_encoding or "utf-8")
  end
  if callback then
    callback(nil, edit)
  end
end

return M
