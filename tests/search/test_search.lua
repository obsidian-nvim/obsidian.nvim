local h = dofile "tests/helpers.lua"
local child

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["find_links"], child = h.child_vault()

T["find_links"]["should find all links in a file"] = function()
  local root = child.lua_get [[tostring(Obsidian.dir)]]
  local filepath = vim.fs.joinpath(root, "test.md")
  local file = [==[
[[link]]
  https://neovim.io <- barelinks should not work
]==]
  vim.fn.writefile(vim.split(file, "\n"), filepath)
  child.lua [[
local search = require"obsidian.search"
local note = require"obsidian.note".from_file(tostring(Obsidian.dir / "test.md"))
_G.res = search.find_links(note, {})
  ]]
  local res = child.lua_get [[res]]

  eq({
    {
      ["end"] = 7,
      line = 1,
      link = "[[link]]",
      start = 0,
    },
  }, res)
end

T["find_links"]["does not include footnote references"] = function()
  local root = child.lua_get [[tostring(Obsidian.dir)]]
  local filepath = vim.fs.joinpath(root, "footnotes.md")
  vim.fn.writefile({ "[[target]] and [^source]", "[^source]: Footnote body" }, filepath)
  child.lua(string.format(
    [=[
    local note = require("obsidian.note").from_file(%q)
    _G.res = require("obsidian.search").find_links(note)
  ]=],
    filepath
  ))

  eq({ { ["end"] = 9, line = 1, link = "[[target]]", start = 0 } }, child.lua_get [[res]])
end

T["find_links"]["reads the live buffer when it is loaded"] = function()
  local root = child.lua_get [[tostring(Obsidian.dir)]]
  local filepath = vim.fs.joinpath(root, "live.md")
  vim.fn.writefile({ "[[on-disk]]" }, filepath)
  child.lua(string.format(
    [=[
    vim.cmd.edit(vim.fn.fnameescape(%q))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "[[unsaved]]" })
    local note = require("obsidian.note").from_buffer(0)
    _G.res = require("obsidian.search").find_links(note)
  ]=],
    filepath
  ))

  eq({
    { ["end"] = 10, line = 1, link = "[[unsaved]]", start = 0 },
  }, child.lua_get [[res]])
end

T["find_links"]["should find links in frontmatter"] = function()
  local root = child.lua_get [[tostring(Obsidian.dir)]]
  local filepath = vim.fs.joinpath(root, "frontmatter.md")
  vim.fn.writefile({ "---", 'related: "[[Target]]"', "---" }, filepath)
  child.lua [[
local search = require"obsidian.search"
local note = require"obsidian.note".from_file(tostring(Obsidian.dir / "frontmatter.md"))
_G.res = search.find_links(note)
  ]]

  eq({
    {
      ["end"] = 19,
      line = 2,
      link = "[[Target]]",
      start = 10,
    },
  }, child.lua_get [[res]])
end

return T
