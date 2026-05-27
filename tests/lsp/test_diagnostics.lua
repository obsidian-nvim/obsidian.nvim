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

T["note write refreshes loaded buffer diagnostics"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "[[target]]",
  })

  child.cmd("edit " .. files["test.md"])
  child.lua [[
    vim.b[0].obsidian_buffer = true
    _G._diagnostic_notifications = {}
    require("obsidian.lsp.util").register_diagnostic_dispatchers {
      notification = function(method, params)
        if method == "textDocument/publishDiagnostics" then
          _G._diagnostic_notifications[#_G._diagnostic_notifications + 1] = params
        end
      end,
    }
    require("obsidian.lsp.diagnostics").publish_unresolved_link_diagnostics(0)
  ]]

  eq(1, child.lua_get [[#_G._diagnostic_notifications[#_G._diagnostic_notifications].diagnostics]])

  child.lua [[
    require("obsidian.note").create { id = "target", verbatim = true }:write()
    vim.wait(2000, function()
      local notifications = _G._diagnostic_notifications
      return #notifications > 1 and #notifications[#notifications].diagnostics == 0
    end, 10)
  ]]

  eq(0, child.lua_get [[#_G._diagnostic_notifications[#_G._diagnostic_notifications].diagnostics]])
end

return T
