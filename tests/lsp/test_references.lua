local eq = MiniTest.expect.equality
local h = dofile "tests/helpers.lua"

local T, child = h.child_vault()

T["find wiki references"] = function()
  local referencer = [==[

[[target]]
]==]

  local root = child.Obsidian.dir
  local referencer_path = root / "referencer.md"
  h.write(referencer, referencer_path)

  local target_path = root / "target.md"
  h.write("", target_path)

  child.cmd(string.format("edit %s", target_path))
  child.lua "vim.lsp.buf.references()"
  local qflist = child.fn.getqflist()
  eq(1, #qflist)
  eq("[[target]]", qflist[1].text)
end

T["find markdown references"] = function()
  local referencer = [==[

[target](target.md)
]==]

  local root = child.Obsidian.dir
  local referencer_path = root / "referencer.md"
  h.write(referencer, referencer_path)

  local target_path = root / "target.md"
  h.write("", target_path)

  child.cmd(string.format("edit %s", target_path))
  child.lua "vim.lsp.buf.references()"
  local qflist = child.fn.getqflist()
  eq(1, #qflist)
  eq("[target](target.md)", qflist[1].text)
end

T["resolve header links"] = function()
  local referencer = [==[


[[target#header]]
]==]

  local referencer_no_header = [==[


[[target]]
]==]

  local target = [==[

# Header
]==]

  local root = child.Obsidian.dir
  local referencer_path = root / "referencer.md"
  h.write(referencer, referencer_path)

  local referencer_no_header_path = root / "referencer_no_header.md"
  h.write(referencer_no_header, referencer_no_header_path)

  local target_path = root / "target.md"
  h.write(target, target_path)

  child.cmd(string.format("edit %s", target_path))

  child.api.nvim_win_set_cursor(0, { 2, 0 })

  child.lua "vim.lsp.buf.references()"
  local qflist = child.fn.getqflist()
  eq(2, #qflist) -- FIX: should be just 1
  eq("[[target#header]]", qflist[1].text)
  eq(3, qflist[1].lnum)
end

T["avoid invalid patterns"] = function()
  local referencer = [==[

(target.md)
]==]

  local root = child.Obsidian.dir
  local referencer_path = root / "referencer.md"
  h.write(referencer, referencer_path)

  local target_path = root / "target.md"
  h.write("", target_path)

  child.cmd(string.format("edit %s", target_path))
  child.lua "vim.lsp.buf.references()"
  local qflist = child.fn.getqflist()
  eq(0, #qflist)
end

T["not find id links, here for historical reasons"] = function()
  local referencer = [==[

[[id]]
]==]

  local root = child.Obsidian.dir
  local referencer_path = root / "referencer.md"
  h.write(referencer, referencer_path)

  local target_path = root / "target.md"
  h.write(
    [[---
id: id
---]],
    target_path
  )

  child.cmd(string.format("edit %s", target_path))
  child.lua "vim.lsp.buf.references()"
  local qflist = child.fn.getqflist()
  eq(0, #qflist)
end

return T
