local eq = MiniTest.expect.equality
local h = dofile "tests/helpers.lua"

local T, child = h.child_vault()

local function flush()
  child.lua [[vim.wait(100, function() end)]]
  child.lua [[vim.wait(100, function() end)]]
end

--- Ensure the LSP client is attached by opening a file in the vault.
local function ensure_lsp(files)
  -- Open any vault file so the LSP client attaches.
  local any_path
  for _, p in pairs(files) do
    any_path = p
    break
  end
  child.cmd("edit " .. any_path)
  flush()
end

--- Request workspace/symbol and return the raw SymbolInformation[] via Lua.
--- Using client.request_sync avoids dealing with quickfix list formatting.
---@param query string
---@return table[]
local function get_symbols(query)
  child.lua(string.format(
    [[
    local clients = vim.lsp.get_clients { name = "obsidian-ls" }
    local client = clients[1]
    local results = client.request_sync("workspace/symbol", { query = %q }, 5000)
    _G._ws_symbols = results and results.result or {}
    ]],
    query
  ))
  flush()
  return child.lua_get "_G._ws_symbols"
end

T["returns note as File symbol"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["my-note.md"] = "",
  })
  ensure_lsp(files)

  local symbols = get_symbols ""
  local found = false
  for _, s in ipairs(symbols) do
    if s.containerName == "my-note" and s.kind == 1 then -- File
      found = true
      break
    end
  end
  eq(true, found)
end

T["returns note aliases as separate File symbols"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["aliased.md"] = [[---
aliases:
  - alias-one
  - alias-two
---]],
  })
  ensure_lsp(files)

  local symbols = get_symbols ""
  local alias_names = {}
  for _, s in ipairs(symbols) do
    if s.containerName == "aliased" and s.kind == 1 then -- File
      alias_names[s.name] = true
    end
  end
  eq(true, alias_names["alias-one"] or false)
  eq(true, alias_names["alias-two"] or false)
end

T["returns headings as String symbols"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["headings.md"] = [[
# Top heading

## Sub heading
]],
  })
  ensure_lsp(files)

  local symbols = get_symbols ""
  local heading_names = {}
  for _, s in ipairs(symbols) do
    if s.kind == 15 then -- String
      heading_names[s.name] = true
    end
  end
  eq(true, heading_names["headings#Top heading"] or false)
  eq(true, heading_names["headings#Sub heading"] or false)
end

T["heading containerName is vault-relative path without .md"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["container-test.md"] = [[
# A heading
]],
  })
  ensure_lsp(files)

  local symbols = get_symbols ""
  for _, s in ipairs(symbols) do
    if s.kind == 15 and s.name:find "A heading" then -- String
      eq("container-test", s.containerName)
      return
    end
  end
  error "heading symbol not found"
end

T["query filters results"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["alpha.md"] = "",
    ["beta.md"] = "",
  })
  ensure_lsp(files)

  local symbols = get_symbols "alpha"
  local found_alpha = false
  local found_beta = false
  for _, s in ipairs(symbols) do
    if s.kind == 1 then -- File
      if s.containerName == "alpha" then
        found_alpha = true
      end
      if s.containerName == "beta" then
        found_beta = true
      end
    end
  end
  eq(true, found_alpha)
  eq(false, found_beta)
end

T["empty query returns all notes"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["one.md"] = "",
    ["two.md"] = "",
    ["three.md"] = "",
  })
  ensure_lsp(files)

  local symbols = get_symbols ""
  local containers = {}
  for _, s in ipairs(symbols) do
    if s.kind == 1 then -- File
      containers[s.containerName] = true
    end
  end
  eq(true, containers["one"] or false)
  eq(true, containers["two"] or false)
  eq(true, containers["three"] or false)
end

T["heading symbol line is correct (0-indexed)"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["lines.md"] = [[first line
second line
## My heading
fourth line
]],
  })
  ensure_lsp(files)

  local symbols = get_symbols ""
  for _, s in ipairs(symbols) do
    if s.kind == 15 and s.name:find "My heading" then
      -- "## My heading" is on line 3 (1-indexed), so 0-indexed = 2
      eq(2, s.location.range.start.line)
      return
    end
  end
  error "heading symbol not found"
end

return T
