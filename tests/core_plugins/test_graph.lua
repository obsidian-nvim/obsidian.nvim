local helpers = require "tests.helpers"
local ignore = require "obsidian.ignore"
local Path = require "obsidian.path"

local T = helpers.temp_vault

T["build_graph"] = MiniTest.new_set()

T["build_graph"]["builds note nodes and links"] = function()
  local graph = require "obsidian.core-plugins.graph"

  local nested = Obsidian.dir / "nested"
  nested:mkdir()

  helpers.write("# A\n[[B]]\n[[nested/C|see C]]\n[also B](B.md)\n", Obsidian.dir / "A.md")
  helpers.write("# B\n[[nested/C#Heading]]\n", Obsidian.dir / "B.md")
  helpers.write("# C\n", nested / "C.md")

  local data = graph.build_graph()
  table.sort(data.links, function(a, b)
    return a.source .. a.target < b.source .. b.target
  end)

  MiniTest.expect.equality(3, #data.nodes)
  MiniTest.expect.equality({
    { source = "A", target = "B" },
    { source = "A", target = "nested/C" },
    { source = "B", target = "nested/C" },
  }, data.links)
end

T["build_graph"]["does not show ignored nodes"] = function()
  local graph = require "obsidian.core-plugins.graph"
  Obsidian.opts.file = {
    ignore_filters = { "archive", "drafts/*.md", "private/**" },
  }
  ignore.clear_cache()

  local archive = Obsidian.dir / "archive"
  local drafts = Obsidian.dir / "drafts"
  local private = Obsidian.dir / "private"
  archive:mkdir()
  drafts:mkdir()
  private:mkdir()

  helpers.write("[[B]] [[archive/Old]] [[drafts/Draft]] [[private/Secret]]", Obsidian.dir / "A.md")
  helpers.write("# B", Obsidian.dir / "B.md")
  helpers.write("# Old", archive / "Old.md")
  helpers.write("# Draft", drafts / "Draft.md")
  helpers.write("# Secret", private / "Secret.md")

  local data = graph.build_graph()
  table.sort(data.nodes, function(a, b)
    return a.id < b.id
  end)

  MiniTest.expect.equality({
    { id = "A", title = "A", path = tostring(Obsidian.dir / "A.md") },
    { id = "B", title = "B", path = tostring(Obsidian.dir / "B.md") },
  }, data.nodes)
  MiniTest.expect.equality({ { source = "A", target = "B" } }, data.links)
end

T["extract_links"] = function()
  local graph = require "obsidian.core-plugins.graph"
  local path = Path.temp { suffix = ".md" }
  helpers.write("[[A|label]] [B](B.md) `[[ignored]]` [site](https://example.com)", path)

  MiniTest.expect.equality({ "A", "B" }, graph.extract_links(path))
  vim.fn.delete(tostring(path))
end

T["current_note_id"] = function()
  local graph = require "obsidian.core-plugins.graph"
  local nested = Obsidian.dir / "nested"
  nested:mkdir()
  local path = nested / "A.md"
  helpers.write("# A", path)

  vim.cmd.edit(vim.fn.fnameescape(tostring(path)))
  MiniTest.expect.equality("nested/A", graph.current_note_id())
  vim.cmd "enew"
end

return T
