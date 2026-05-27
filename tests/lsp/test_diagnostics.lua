local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

local function collect()
  child.lua [[
    _G._diagnostics = require("obsidian.lsp.diagnostics").collect_unresolved_link_diagnostics(0)
  ]]
  return child.lua_get [[_G._diagnostics]]
end

T["unresolved links"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = table.concat({
      "# Heading",
      "[[target]]",
      "[[missing]]",
      "[missing markdown](missing.md)",
      "[external](https://example.com)",
      "[[#Heading]]",
      "[[#Missing Heading]]",
      "```",
      "[[ignored]]",
      "```",
    }, "\n"),
    ["target.md"] = "",
  })

  child.cmd("edit " .. files["test.md"])

  local diagnostics = collect()
  eq(3, #diagnostics)
  eq("Unresolved link: missing", diagnostics[1].message)
  eq("Unresolved link: missing.md", diagnostics[2].message)
  eq("Unresolved link: #missing heading", diagnostics[3].message)
end

return T
