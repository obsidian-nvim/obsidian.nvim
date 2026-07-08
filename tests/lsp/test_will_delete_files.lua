local eq = MiniTest.expect.equality
local h = dofile "tests/helpers.lua"

local T, child = h.child_vault()

T["initialize advertises willDeleteFiles note support"] = function()
  child.lua [[
    local handler = require "obsidian.lsp.handlers.initialize"

    handler(vim.empty_dict(), function(_, res)
      _G.will_delete_filter = res.capabilities.workspace.fileOperations.willDelete.filters[1]
    end, {
      notification = function() end,
    })
  ]]

  eq("file", child.lua_get "will_delete_filter.scheme")
  eq("**/*.md", child.lua_get "will_delete_filter.pattern.glob")
  eq("file", child.lua_get "will_delete_filter.pattern.matches")
end

T["willDeleteFiles runs note delete flow without deleting the note"] = function()
  child.lua [[
    local handler = require "obsidian.lsp.handlers.will_delete_files"
    local note_path = tostring(Obsidian.dir / "deleteme.md")
    vim.fn.writefile({ "# delete me" }, note_path)

    handler({
      files = {
        { uri = vim.uri_from_fname(note_path) },
      },
    }, function(err, result)
      _G.delete_err = err
      _G.delete_result = result
    end)

    _G.note_exists_after_will_delete = vim.uv.fs_stat(note_path) ~= nil
  ]]

  eq(vim.NIL, child.lua_get "delete_err")
  eq(true, child.lua_get "note_exists_after_will_delete")
end

return T
