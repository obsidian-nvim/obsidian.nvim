local eq = MiniTest.expect.equality
local h = dofile "tests/helpers.lua"

local T, child = h.child_vault()

local function open(contents)
  local files = h.mock_vault_contents(child.Obsidian.dir, contents)
  child.lua [[Obsidian.opts.frontmatter.enabled = false]]
  child.cmd("edit " .. files["a.md"])
  return files
end

T["block.rename applies by default"] = function()
  local files = open { ["a.md"] = "text ^old", ["b.md"] = "[[a#^old]]" }

  eq(
    true,
    h.child_await(child, [[require("obsidian.block").rename(0, "old", "new", function(err) done(err or true) end)]])
  )
  child.cmd "silent! wall"

  eq({ "text ^new" }, h.read(files["a.md"]))
  eq({ "[[a#^new]]" }, h.read(files["b.md"]))
end

T["header.rename with apply false returns the edit only"] = function()
  open { ["a.md"] = "# Old\n\nsee [[#Old]]" }

  local out = h.child_await(
    child,
    [[require("obsidian.header").rename(0, "Old", "New", { apply = false }, function(err, edit)
      done({ err = err or false, has_edit = edit ~= nil })
    end)]]
  )

  eq({ err = false, has_edit = true }, out)
  eq({ "# Old", "", "see [[#Old]]" }, child.api.nvim_buf_get_lines(0, 0, -1, false))
end

T["header.rename applies by default"] = function()
  local files = open { ["a.md"] = "# Old\n\nsee [[#Old]]" }

  eq(
    true,
    h.child_await(child, [[require("obsidian.header").rename(0, "Old", "New", function(err) done(err or true) end)]])
  )
  child.cmd "silent! wall"

  eq({ "# New", "", "see [[#New]]" }, h.read(files["a.md"]))
end

T["tag.rename applies across the vault"] = function()
  local files = open {
    ["a.md"] = "---\ntags:\n  - old\n---\n#old #old/sub",
    ["b.md"] = "#old",
  }

  eq(
    true,
    h.child_await(child, [[require("obsidian.tag").rename("old", "fresh", function(err) done(err or true) end)]])
  )
  child.cmd "silent! wall"

  eq({ "---", "tags:", "  - fresh", "---", "#fresh #fresh/sub" }, h.read(files["a.md"]))
  eq({ "#fresh" }, h.read(files["b.md"]))
end

T["footnotes.rename applies by default"] = function()
  local files = open { ["a.md"] = "text[^1]\n\n[^1]: note" }

  eq(
    true,
    h.child_await(child, [[require("obsidian.footnotes").rename(0, "1", "src", function(err) done(err or true) end)]])
  )
  child.cmd "silent! wall"

  eq({ "text[^src]", "", "[^src]: note" }, h.read(files["a.md"]))
end

T["rename without callback and apply false is refused"] = function()
  open { ["a.md"] = "text ^old" }

  h.child_await(child, [[require("obsidian.block").rename(0, "old", "new", { apply = false }); done(true)]])

  eq({ "text ^old" }, child.api.nvim_buf_get_lines(0, 0, -1, false))
end

return T
