local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

local function analyze(source)
  child.lua(([[
    require("obsidian.lsp.diagnostics").publish({
      textDocument = {
        uri = vim.uri_from_fname(tostring(Obsidian.dir / "current.md")),
        text = %q,
      },
    }, {
      notification = function(method, params)
        assert(method == "textDocument/publishDiagnostics")
        _G.diagnostics_result = params.diagnostics
      end,
    })
  ]]):format(source))
  return child.lua_get "diagnostics_result"
end

T["reports Marksman's three most useful diagnostics"] = function()
  local nbsp = "\194\160"
  local diagnostics = analyze(table.concat({
    "# Repeated",
    "# Repeated",
    "[[#repeated]]",
    "[[#missing]]",
    "##" .. nbsp .. "Not a heading",
  }, "\n"))

  eq(3, #diagnostics)
  eq("ambiguous-link", diagnostics[1].code)
  eq("Ambiguous link to heading 'repeated'", diagnostics[1].message)
  eq(vim.diagnostic.severity.HINT, diagnostics[1].severity)
  eq({ line = 2, character = 0 }, diagnostics[1].range.start)

  eq("broken-link", diagnostics[2].code)
  eq("Link to non-existent heading 'missing'", diagnostics[2].message)
  eq(vim.diagnostic.severity.HINT, diagnostics[2].severity)

  eq("non-breaking-whitespace", diagnostics[3].code)
  eq(vim.diagnostic.severity.WARN, diagnostics[3].severity)
  eq({ line = 4, character = 2 }, diagnostics[3].range.start)
  eq({ line = 4, character = 3 }, diagnostics[3].range["end"])
end

T["ignores valid links, code, frontmatter, URLs, and attachments"] = function()
  local diagnostics = analyze [=[---
aliases: ["[[not-a-note]]"]
---
# Existing
[[#existing]]
`[[inline-code]]`
```
[[fenced-code]]
```
[website](https://example.com)
[image](image.png)]=]

  eq({}, diagnostics)
end

T["resolves documents and their headings from the cache"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["target.md"] = "---\nid: target-id\naliases: [alias]\n---\n# Existing",
  })
  child.lua [[
    local cache = require "obsidian.cache"
    cache.setup { enabled = true, backend = "memory" }
    assert(vim.wait(1000, function()
      return cache.is_ready()
    end))
  ]]
  local diagnostics = analyze(table.concat({
    "[[target]]",
    "[[target-id#existing]]",
    "[[alias#existing]]",
    "[[target#missing]]",
  }, "\n"))

  eq(1, #diagnostics)
  eq("broken-link", diagnostics[1].code)
  eq("Link to non-existent heading 'missing' in document 'target'", diagnostics[1].message)
end

T["uses hint severity for broken Markdown links"] = function()
  local diagnostics = analyze "[missing](#missing)"

  eq(1, #diagnostics)
  eq("broken-link", diagnostics[1].code)
  eq(vim.diagnostic.severity.HINT, diagnostics[1].severity)
end

T["debounces document changes"] = function()
  child.lua [=[
    local diagnostics = require "obsidian.lsp.diagnostics"
    local uri = vim.uri_from_fname(tostring(Obsidian.dir / "current.md"))
    local dispatchers = {
      notification = function(_, params)
        _G.debounce_notifications = (_G.debounce_notifications or 0) + 1
        _G.debounce_diagnostics = params.diagnostics
      end,
    }
    _G.debounce_notifications = 0
    for _, text in ipairs({ "[[#first]]", "[[#second]]", "# Existing\n[[#existing]]" }) do
      diagnostics.schedule({
        textDocument = { uri = uri },
        contentChanges = { { text = text } },
      }, dispatchers)
    end
    assert(vim.wait(250, function()
      return _G.debounce_notifications > 0
    end) == false)
    assert(vim.wait(1000, function()
      return _G.debounce_notifications == 1
    end))
  ]=]

  eq(1, child.lua_get "debounce_notifications")
  eq({}, child.lua_get "debounce_diagnostics")
end

return T
