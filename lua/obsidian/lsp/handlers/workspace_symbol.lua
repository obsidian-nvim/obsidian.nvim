local search = require "obsidian.search"
local async = require "obsidian.async"
local util = require "obsidian.util"

-- LSP SymbolKind constants.
local SymbolKind = {
  File = 1,
  Enum = 10,
  String = 15,
}

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
---@return lsp.SymbolInformation[]
local function note_to_symbols(note)
  local uri = vim.uri_from_fname(tostring(note.path))
  assert(note.path)
  local container = relative_path_no_ext(note.path)
  local location = {
    uri = uri,
    range = {
      start = { line = 0, character = 0 },
      ["end"] = { line = 0, character = 0 },
    },
  }

  ---@type lsp.SymbolInformation[]
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

---@param heading obsidian.HeadingLocation
---@return lsp.SymbolInformation
local function heading_to_symbol(heading)
  local container = relative_path_no_ext(heading.path)
  local name = container .. "#" .. heading.heading
  local uri = vim.uri_from_fname(tostring(heading.path))
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
  }
end

---@param params lsp.WorkspaceSymbolParams
---@param handler fun(_: any, result: lsp.SymbolInformation[])
return function(params, handler)
  local query = params.query or ""

  async.run(function()
    ---@type lsp.SymbolInformation[]
    local symbols = {}

    -- Run all searches in parallel.
    async.join(10, {
      function()
        local notes = async.await(2, search.find_notes_async, query, { search = { ignore_case = true } })
        for _, note in ipairs(notes) do
          vim.list_extend(symbols, note_to_symbols(note))
        end
      end,
      function()
        local headings = async.await(2, search.find_headings_async, query)
        for _, heading in ipairs(headings) do
          symbols[#symbols + 1] = heading_to_symbol(heading)
        end
      end,
    })

    handler(nil, symbols)
  end)
end
