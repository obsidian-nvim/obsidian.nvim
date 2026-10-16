local search = require "obsidian.search"
local async = require "obsidian.async"
local fs_util = require "obsidian.util.fs"
local Range = require "obsidian.range"
local api = require "obsidian.api"
local SymbolKind = vim.lsp.protocol.SymbolKind

---@class obsidian.lsp.SymbolMetadata
---@field note obsidian.Note
---@field section obsidian.Section|?
---@field range lsp.Range|?

--- Compute the vault-relative path without the .md extension.
---@param abs_path string|obsidian.Path
---@return string
local function relative_path_no_ext(abs_path)
  local rel = fs_util.relpath(tostring(api.resolve_workspace_dir(abs_path)), tostring(abs_path))
  if rel and vim.endswith(rel, ".md") then
    rel = rel:sub(1, -4)
  end
  return rel or tostring(abs_path)
end

---@param note obsidian.Note
---@return lsp.WorkspaceSymbol[]
local function note_to_symbols(note)
  assert(note.path, "Note must have a path")
  local uri = vim.uri_from_fname(tostring(note.path))
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
    data = {
      note = note,
    },
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
        data = {
          note = note,
        },
      }
    end
  end

  return symbols
end

---@param note obsidian.Note
---@param section obsidian.Section
---@return lsp.WorkspaceSymbol
local function section_to_symbol(note, section)
  assert(note.path, "Note must have a path")
  local container = relative_path_no_ext(note.path)
  local name = container .. "#" .. section.header
  local uri = vim.uri_from_fname(tostring(note.path))
  local range = Range.to_lsp(section.range, "utf-8")

  return {
    name = name,
    kind = SymbolKind.String,
    location = {
      uri = uri,
      range = range,
    },
    containerName = container,
    data = {
      note = note,
      section = section,
      range = range,
    },
  }
end

---@param match obsidian.search.HeadingMatch
---@return lsp.WorkspaceSymbol
local function heading_to_symbol(match)
  return section_to_symbol(match.note, assert(match.heading.section, "heading match has no section"))
end

---@param query string
---@param callback fun(result: lsp.WorkspaceSymbol[])
return function(query, callback)
  query = query or ""
  callback = vim.schedule_wrap(callback)

  async.run(function()
    ---@type lsp.WorkspaceSymbol[]
    local symbols = {}

    local notes = async.await(2, search.find_notes_async, query, nil)
    local headings = async.await(2, search.find_headings_async, query, nil)

    for _, note in ipairs(notes) do
      vim.list_extend(symbols, note_to_symbols(note))
    end
    for _, heading in ipairs(headings) do
      symbols[#symbols + 1] = heading_to_symbol(heading)
    end

    callback(symbols)
  end)
end
