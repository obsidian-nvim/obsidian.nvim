local search = require "obsidian.search"
local async = require "obsidian.async"
local util = require "obsidian.util"
local SymbolKind = vim.lsp.protocol.SymbolKind

--- Compute the vault-relative path without the .md extension.
---@param abs_path string|obsidian.Path
---@return string
local function relative_path_no_ext(abs_path)
  local rel = util.relpath(tostring(Obsidian.dir), tostring(abs_path))
  if rel and vim.endswith(rel, ".md") then
    rel = rel:sub(1, -4)
  end
  return rel or tostring(abs_path)
end

---@param note obsidian.Note
---@return lsp.WorkspaceSymbol[]
local function note_to_symbols(note)
  local uri = vim.uri_from_fname(tostring(note.path))
  assert(note.path, "Note must have a path")
  local container = relative_path_no_ext(note.path)
  local location = {
    uri = uri,
    range = {
      start = { line = 0, character = 0 },
      ["end"] = { line = 0, character = 0 },
    },
  }

  ---@type lsp.WorkspaceSymbol[]
  local symbols = {}

  -- Primary symbol: display name.
  symbols[#symbols + 1] = {
    name = note:display_name(),
    kind = SymbolKind.File,
    location = location,
    containerName = container,
  }

  -- Additional symbols for each alias.
  for _, alias in ipairs(note.aliases) do
    -- Skip if alias is the same as the display name (already emitted).
    if alias ~= note:display_name() then
      symbols[#symbols + 1] = {
        name = alias,
        kind = SymbolKind.File,
        location = location,
        containerName = container,
      }
    end
  end

  return symbols
end

---@param note obsidian.Note
---@param heading obsidian.note.HeaderAnchor
---@return lsp.WorkspaceSymbol
local function heading_to_symbol(note, heading)
  assert(note.path, "Note must have a path")
  local container = relative_path_no_ext(note.path)
  local name = container .. "#" .. heading.header
  local uri = vim.uri_from_fname(tostring(note.path))
  local line = heading.line - 1 -- 0-indexed
  return {
    name = name,
    kind = SymbolKind.String,
    location = {
      uri = uri,
      range = {
        start = { line = line, character = 0 },
        ["end"] = { line = line, character = 0 },
      },
    },
    containerName = container,
    data = heading,
  }
end

---@param heading obsidian.note.HeaderAnchor
---@return boolean
local function is_standalone_heading_anchor(heading)
  return string.find(heading.anchor, "#", 2, true) == nil
end

---@param heading obsidian.note.HeaderAnchor
---@param query string
---@return boolean
local function heading_matches_query(heading, query)
  return query == "" or string.find(string.lower(heading.header), string.lower(query), 1, true) ~= nil
end

---@param note obsidian.Note
---@param query string
---@return lsp.WorkspaceSymbol[]
local function note_heading_symbols(note, query)
  ---@type obsidian.note.HeaderAnchor[]
  local headings = {}

  for _, heading in pairs(note.anchor_links or {}) do
    if is_standalone_heading_anchor(heading) and heading_matches_query(heading, query) then
      headings[#headings + 1] = heading
    end
  end

  table.sort(headings, function(a, b)
    if a.line ~= b.line then
      return a.line < b.line
    end
    return a.anchor < b.anchor
  end)

  return vim.tbl_map(function(heading)
    return heading_to_symbol(note, heading)
  end, headings)
end

---@param query string
---@param callback fun(result: lsp.WorkspaceSymbol[])
return function(query, callback)
  query = query or ""

  async.run(function()
    ---@type lsp.WorkspaceSymbol[]
    local symbols = {}

    local notes = async.await(2, search.find_notes_async, query, nil, {
      search = { ignore_case = true },
      notes = { collect_anchor_links = true },
    })

    for _, note in ipairs(notes) do
      vim.list_extend(symbols, note_to_symbols(note))
      vim.list_extend(symbols, note_heading_symbols(note, query))
    end

    callback(symbols)
  end)
end
