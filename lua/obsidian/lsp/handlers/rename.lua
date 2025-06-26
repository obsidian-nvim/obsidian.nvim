local lsp = vim.lsp
local Path = require "obsidian.path"
local Note = require "obsidian.note"
local search = require "obsidian.search"

---@param old_uri string
---@param new_uri string
local function rename_file(old_uri, new_uri)
  -- ---@type lsp.WorkspaceEdit
  -- local edit = {
  --   documentChanges = {
  --     {
  --       kind = "rename",
  --       oldUri = old_uri,
  --       newUri = new_uri,
  --     },
  --   },
  -- }
  -- lsp.util.apply_workspace_edit(edit, "utf-8")
end

-- Search notes on disk for any references to `cur_note_id`.
-- We look for the following forms of references:
-- * '[[cur_note_id]]'
-- * '[[cur_note_id|ALIAS]]'
-- * '[[cur_note_id\|ALIAS]]' (a wiki link within a table)
-- * '[ALIAS](cur_note_id)'
-- And all of the above with relative paths (from the vault root) to the note instead of just the note ID,
-- with and without the ".md" suffix.
-- Another possible form is [[ALIAS]], but we don't change the note's aliases when renaming
-- so those links will still be valid.
local ref_patterns = {
  "[[%s]]", -- wiki
  "[[%s|", -- wiki with alias
  "[[%s\\|", -- wiki link within a table
  "[[%s#", -- wiki with heading
  "](%s)", -- markdown
  "](%s#", -- markdown with heading
}

---@class obsidian.lsp.note_info
---@field id string
---@field rel_path string
---@field path string

local function build_search_lookup(old, new)
  local replace_lookup = {}

  for _, pat in ipairs(ref_patterns) do
    replace_lookup[pat:format(old.id)] = pat:format(new.id)
    replace_lookup[pat:format(old.rel_path)] = pat:format(new.rel_path)
    replace_lookup[pat:format(old.rel_path:sub(1, -4))] = pat:format(new.rel_path:sub(1, -4))
  end

  return replace_lookup, vim.tbl_keys(replace_lookup)
end

---@return obsidian.lsp.note_info
local function info_from_uri(uri, client)
  local path = vim.uri_to_fname(uri)
  local rel_path = tostring(client:vault_relative_path(path, { strict = true }))

  local note = Note.from_file(path)
  local id = tostring(note.id)

  return {
    rel_path = rel_path,
    path = path,
    id = id,
  }
end

--- TODO: should move to other dirs, with new name like ../newname

---@return obsidian.lsp.note_info
local function info_from_id(id, old_path, client)
  local dirname = vim.fs.dirname(old_path)

  local path = vim.fs.joinpath(dirname, id) .. ".md"
  local rel_path = tostring(client:vault_relative_path(path, { strict = true }))

  return {
    rel_path = rel_path,
    path = path,
    id = id,
  }
end

---@param client obsidian.Client
---@param params lsp.RenameParams
local function rename_current_note(client, params)
  local old = info_from_uri(params.textDocument.uri, client)
  local new = info_from_id(params.newName, old.path, client)

  local search_lookup = build_search_lookup(old, new)

  search.search_async(
    client.dir,
    vim.tbl_keys(search_lookup),
    search.SearchOpts.from_tbl { fixed_strings = true, max_count_per_file = 1 },
    vim.schedule_wrap(function(match)
      local file = match.path.text
      local line = match.line_number - 1
      local start, _end = match.submatches[1].start, match.submatches[1]["end"]
      local matched = match.submatches[1].match.text
      local edit = {
        documentChanges = {
          {
            textDocument = {
              uri = vim.uri_from_fname(file),
            },
            edits = {
              {
                range = {
                  start = { line = line, character = start },
                  ["end"] = { line = line, character = _end },
                },
                newText = search_lookup[matched],
              },
            },
          },
        },
      }
      lsp.util.apply_workspace_edit(edit, "utf-8")
    end),
    function(_)
      -- TODO: conclude the rename
    end
  )

  vim.lsp.util.rename(old.path, new.path)

  -- local note = client:current_note()
  -- note.id = new_note_id
end

local function rename_note_at_cursor(params) end

---@param client obsidian.Client
---@param params table
return function(client, params, _, _)
  local position = params.position

  -- TODO: check if cursor on link
  rename_current_note(client, params)
end
