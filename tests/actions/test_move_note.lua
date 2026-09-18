local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

T["move_note saves moved buffer without E13"] = function()
  local folder = child.Obsidian.dir / "folder"
  folder:mkdir()
  local dest = tostring(folder / "note.md")
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["note.md"] = "original",
  })

  child.cmd("edit " .. vim.fn.fnameescape(files["note.md"]))
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "changed" })

  child.lua(([[
    vim.b.obsidian_buffer = true
    local picker = require "obsidian.picker"
    picker.select = function(_, _, on_choice)
      on_choice { { filename = %q, text = "folder/" } }
    end
    require("obsidian.actions").move_note()
  ]]):format(tostring(folder)))

  eq(vim.fs.normalize(dest), vim.fs.normalize(child.api.nvim_buf_get_name(0)))
  eq(nil, vim.uv.fs_stat(files["note.md"]))
  assert(vim.uv.fs_stat(dest), "moved note should exist")
  eq(false, child.bo.modified)

  local line_count = child.api.nvim_buf_line_count(0)
  child.api.nvim_buf_set_lines(0, line_count, line_count, false, { "again" })
  child.lua [[
    local ok, err = pcall(vim.cmd, "write")
    assert(ok, err)
  ]]
  local lines = h.read(dest)
  eq("again", lines[#lines])
end

return T
