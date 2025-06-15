local lsp = vim.lsp
local search = require "obsidian.search"
local util = require "obsidian.util"

-- TODO: define rename, rename can:
-- 1. rename base name
-- 2. rename id? option?

---@param client obsidian.Client
---@param params lsp.RenameParams
local function rename_current_note(client, params)
  local old = util.info_from_uri(params.textDocument.uri, client)
  local new = util.info_from_base(params.newName, old.dirname, client)
  local replace_lookup = util.build_replace_lookup(old, new) -- { [old]: new }
  local reference_forms = vim.tbl_keys(replace_lookup) -- old[]

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
    end
  )
  lsp.util.rename(old.path, new.path)

  local note = client:current_note()
  note.id = new.id
end

-- local function rename_note_at_cursor(client, params) end

---@param client obsidian.Client
---@param params table
return function(client, params, _, _)
  if util.cursor_on_markdown_link() then
    vim.notify "cursor rename not implemented"
    return
    -- rename_note_at_cursor(client, params)
  else
    rename_current_note(client, params)
  end
end
