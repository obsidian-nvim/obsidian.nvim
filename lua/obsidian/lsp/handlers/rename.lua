local lsp = vim.lsp
local Path = require "obsidian.path"
local Note = require "obsidian.note"
local search = require "obsidian.search"

---@param old_uri string
---@param new_uri string
local function rename_file(old_uri, new_uri)
  ---@type lsp.WorkspaceEdit
  local edit = {
    documentChanges = {
      {
        kind = "rename",
        oldUri = old_uri,
        newUri = new_uri,
      },
    },
  }

  lsp.util.apply_workspace_edit(edit, "utf-8")
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

---@param client obsidian.Client
---@param params lsp.RenameParams
local function rename_current_note(client, params)
  local new_note_id = params.newName
  local uri = params.textDocument.uri
  local current_file = vim.uri_to_fname(uri)
  local dirname = vim.fs.dirname(current_file)

  local new_path = vim.fs.joinpath(dirname, new_note_id) .. ".md"
  local new_note_path = Path.new(new_path)

  local cur_note_bufnr = vim.uri_to_bufnr(uri)
  local cur_note_path = Path.buffer(cur_note_bufnr)
  local cur_note = Note.from_file(cur_note_path)
  local cur_note_id = tostring(cur_note.id)

  local cur_note_rel_path = tostring(client:vault_relative_path(cur_note_path, { strict = true }))
  local new_note_rel_path = tostring(client:vault_relative_path(new_note_path, { strict = true }))

  local replace_lookup = {}

  for _, pat in ipairs(ref_patterns) do
    replace_lookup[pat:format(cur_note_id)] = pat:format(new_note_id)
    replace_lookup[pat:format(cur_note_rel_path)] = pat:format(new_note_rel_path)
    replace_lookup[pat:format(cur_note_rel_path:sub(1, -4))] = pat:format(new_note_rel_path:sub(1, -4))
  end

  local reference_forms = vim.tbl_keys(replace_lookup)

  search.search_async(
    client.dir,
    reference_forms,
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
                newText = replace_lookup[matched],
              },
            },
          },
        },
      }
      lsp.util.apply_workspace_edit(edit, "utf-8")
    end),
    function(_)
      -- TODO: conclude the rename
      -- all_tasks_submitted = true
    end
  )
  rename_file(uri, vim.uri_from_fname(new_path))

  local note = client:current_note()
  note.id = new_note_id
end

local function rename_note_at_cursor(params) end

---@param client obsidian.Client
---@param params table
return function(client, params, _, _)
  local position = params.position

  -- TODO: check if cursor on link
  rename_current_note(client, params)

  -- require "obsidian.commands.rename"(obsidian_client, { args = params.newName })
end
