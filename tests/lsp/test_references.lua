local eq = MiniTest.expect.equality
local h = dofile "tests/helpers.lua"

local T, child = h.child_vault()

local function get_refs()
  return h.child_await(
    child,
    [[
      require("obsidian.lsp.handlers._references")(nil, {}, function(_, locations)
        local refs = {}
        for _, loc in ipairs(locations or {}) do
          local path = vim.uri_to_fname(loc.uri)
          local lnum = loc.range.start.line + 1
          local lines = vim.fn.readfile(path)
          refs[#refs + 1] = {
            filename = path,
            lnum = lnum,
            text = lines[lnum],
            col = loc.range.start.character + 1,
            end_col = loc.range["end"].character + 1,
          }
        end
        done(refs)
      end)
    ]],
    { desc = "references" }
  )
end

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
  local qflist = get_refs()
  eq(1, #qflist)
  eq("[[target]]", qflist[1].text)
end

T["find wiki references under cursor"] = function()
  local referencer = [==[

[[target]]
]==]

  local root = child.Obsidian.dir
  local referencer_path = root / "referencer.md"
  h.write(referencer, referencer_path)

  local target_path = root / "target.md"
  h.write("", target_path)

  child.cmd(string.format("edit %s", referencer_path))
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  local qflist = get_refs()
  eq(1, #qflist)
  eq("[[target]]", qflist[1].text)
end

T["find unresolved wiki references under cursor"] = function()
  local referencer = [==[

[[missing]]

[[missing]]
]==]

  local root = child.Obsidian.dir
  local referencer_path = root / "referencer.md"
  h.write(referencer, referencer_path)

  child.cmd(string.format("edit %s", referencer_path))
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  local qflist = get_refs()
  eq(2, #qflist)
  eq("[[missing]]", qflist[1].text)
  eq("[[missing]]", qflist[2].text)
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
  local qflist = get_refs()
  eq(1, #qflist)
  eq("[target](target.md)", qflist[1].text)
end

T["find markdown references under cursor"] = function()
  local referencer = [==[

[target](target.md)
]==]

  local root = child.Obsidian.dir
  local referencer_path = root / "referencer.md"
  h.write(referencer, referencer_path)

  local target_path = root / "target.md"
  h.write("", target_path)

  child.cmd(string.format("edit %s", referencer_path))
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  local qflist = get_refs()
  eq(1, #qflist)
  eq("[target](target.md)", qflist[1].text)
end

T["find tag references under cursor"] = function()
  local file = [==[

#tag

#tag
]==]

  local root = child.Obsidian.dir
  local file_path = root / "file.md"
  h.write(file, file_path)

  child.cmd(string.format("edit %s", file_path))
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  local qflist = get_refs()
  eq(2, #qflist)
  eq("#tag", qflist[1].text)
end

T["resolve header links under cursor"] = function()
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

  local qflist = get_refs()
  eq(1, #qflist)
  eq("[[target#header]]", qflist[1].text)
  eq(3, qflist[1].lnum)
end

T["resolve blocks under cursor"] = function()
  local file = [==[

[[file#^123]]

block ^123
]==]

  local root = child.Obsidian.dir
  local file_path = root / "file.md"
  h.write(file, file_path)

  child.cmd(string.format("edit %s", file_path))
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  local qflist = get_refs()
  eq(1, #qflist)
  eq("[[file#^123]]", qflist[1].text)
end

T["find block references under cursor"] = function()
  local file = [==[

[[#^123]]

block ^123
]==]

  local root = child.Obsidian.dir
  local file_path = root / "file.md"
  h.write(file, file_path)

  child.cmd(string.format("edit %s", file_path))
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  local qflist = get_refs()
  eq(1, #qflist)
  eq("[[#^123]]", qflist[1].text)
end

T["find anchor references under cursor"] = function()
  local file = [==[

[[#header]]

# header
]==]

  local root = child.Obsidian.dir
  local file_path = root / "file.md"
  h.write(file, file_path)

  child.cmd(string.format("edit %s", file_path))
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  local qflist = get_refs()
  eq(1, #qflist)
  eq("[[#header]]", qflist[1].text)
end

T["find fragment-only anchor references only in current note"] = function()
  local root = child.Obsidian.dir
  local file_path = root / "file.md"
  h.write(
    [==[

[[#header]]

# header
]==],
    file_path
  )
  h.write(
    [==[

[[#other]]

# other
]==],
    root / "other.md"
  )

  child.cmd(string.format("edit %s", file_path))
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  local qflist = get_refs()
  eq(1, #qflist)
  eq("[[#header]]", qflist[1].text)
end

T["find block references from inline block id under cursor"] = function()
  local root = child.Obsidian.dir
  local file_path = root / "file.md"
  h.write(
    [==[
[[#^123]]

block ^123

[[file]]
]==],
    file_path
  )

  child.cmd(string.format("edit %s", file_path))
  child.api.nvim_win_set_cursor(0, { 3, 7 })
  local qflist = get_refs()
  eq(1, #qflist)
  eq("[[#^123]]", qflist[1].text)
end

T["find footnote references under cursor"] = function()
  local file = [==[
some claim[^1]

another mention[^1]

[^1]: the footnote
]==]

  local root = child.Obsidian.dir
  local file_path = root / "file.md"
  h.write(file, file_path)

  child.cmd(string.format("edit %s", file_path))
  child.api.nvim_win_set_cursor(0, { 1, 11 })
  local qflist = get_refs()
  eq(3, #qflist)
  eq("some claim[^1]", qflist[1].text)
  eq(11, qflist[1].col)
  eq("another mention[^1]", qflist[2].text)
  eq("[^1]: the footnote", qflist[3].text)
end

T["find footnote references from definition"] = function()
  local file = [==[
some claim[^1]

[^1]: the footnote
]==]

  local root = child.Obsidian.dir
  local file_path = root / "file.md"
  h.write(file, file_path)

  child.cmd(string.format("edit %s", file_path))
  child.api.nvim_win_set_cursor(0, { 3, 0 })
  local qflist = get_refs()
  eq(2, #qflist)
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
  local qflist = get_refs()
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
  local qflist = get_refs()
  eq(0, #qflist)
end

return T
