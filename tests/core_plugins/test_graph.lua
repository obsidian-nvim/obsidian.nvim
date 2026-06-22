local helpers = require "tests.helpers"
local ignore = require "obsidian.ignore"

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

T["build_graph"]["adds linked attachments and missing notes"] = function()
  local graph = require "obsidian.core-plugins.graph"
  local assets = Obsidian.dir / "assets"
  assets:mkdir()

  helpers.write("![[assets/image.png]]\n[[Missing]]", Obsidian.dir / "A.md")
  helpers.write("png", assets / "image.png")

  local data = graph.build_graph()
  table.sort(data.nodes, function(a, b)
    return a.id < b.id
  end)
  table.sort(data.links, function(a, b)
    return a.source .. a.target < b.source .. b.target
  end)

  MiniTest.expect.equality({
    { id = "A", title = "A", path = tostring(Obsidian.dir / "A.md"), folder = "", aliases = {}, tags = {} },
    { id = "Missing", title = "Missing", folder = "", aliases = {}, tags = {}, exists = false },
    {
      id = "assets/image.png",
      title = "image.png",
      path = tostring(assets / "image.png"),
      folder = "assets",
      aliases = {},
      tags = {},
      type = "attachment",
      exists = true,
    },
  }, data.nodes)
  MiniTest.expect.equality({
    { source = "A", target = "Missing" },
    { source = "A", target = "assets/image.png" },
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
    { id = "A", title = "A", path = tostring(Obsidian.dir / "A.md"), folder = "", aliases = {}, tags = {} },
    { id = "B", title = "B", path = tostring(Obsidian.dir / "B.md"), folder = "", aliases = {}, tags = {} },
  }, data.nodes)
  MiniTest.expect.equality({ { source = "A", target = "B" } }, data.links)
end

T["build_graph"]["reads frontmatter metadata and resolves aliases"] = function()
  local graph = require "obsidian.core-plugins.graph"
  local nested = Obsidian.dir / "nested"
  nested:mkdir()

  helpers.write("---\naliases: [Alias B]\ntags: [project, graph]\ntitle: Better B\n---\n# B\n#inline", nested / "B.md")
  helpers.write("[[Alias B]]", Obsidian.dir / "A.md")

  local data = graph.build_graph()
  table.sort(data.nodes, function(a, b)
    return a.id < b.id
  end)
  table.sort(data.links, function(a, b)
    return a.source .. a.target < b.source .. b.target
  end)

  MiniTest.expect.equality({
    { id = "A", title = "A", path = tostring(Obsidian.dir / "A.md"), folder = "", aliases = {}, tags = {} },
    {
      id = "nested/B",
      title = "Better B",
      path = tostring(nested / "B.md"),
      folder = "nested",
      aliases = { "Alias B" },
      tags = { "project", "graph", "inline" },
    },
    { id = "tag:graph", title = "#graph", folder = "", aliases = {}, tags = {}, type = "tag" },
    { id = "tag:inline", title = "#inline", folder = "", aliases = {}, tags = {}, type = "tag" },
    { id = "tag:project", title = "#project", folder = "", aliases = {}, tags = {}, type = "tag" },
  }, data.nodes)
  MiniTest.expect.equality({
    { source = "A", target = "nested/B" },
    { source = "nested/B", target = "tag:graph" },
    { source = "nested/B", target = "tag:inline" },
    { source = "nested/B", target = "tag:project" },
  }, data.links)
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

T["note_path_by_id"] = function()
  local graph = require "obsidian.core-plugins.graph"
  local path = Obsidian.dir / "A.md"
  helpers.write("# A", path)

  MiniTest.expect.equality(tostring(path), graph.note_path_by_id "A")
  MiniTest.expect.equality(nil, graph.note_path_by_id "missing")
end

T["open_note_by_id"] = function()
  local graph = require "obsidian.core-plugins.graph"
  local path = Obsidian.dir / "A.md"
  helpers.write("# A", path)

  local ok, err = graph.open_note_by_id("A", "edit")
  MiniTest.expect.equality(true, ok)
  MiniTest.expect.equality(nil, err)
  vim.wait(1000, function()
    return vim.api.nvim_buf_get_name(0) == tostring(path)
  end)
  MiniTest.expect.equality(tostring(path), vim.api.nvim_buf_get_name(0))

  ok, err = graph.open_note_by_id("missing", "edit")
  MiniTest.expect.equality(false, ok)
  MiniTest.expect.equality("note not found", err)
  vim.cmd "enew!"
end

T["live graph watches create/delete only"] = function()
  local graph = require "obsidian.core-plugins.graph"
  local watchfiles = require "obsidian.lsp.watchfiles"
  local FileChangeType = vim.lsp.protocol.FileChangeType
  local calls = {}
  local original_schedule = graph.schedule_graph_update

  graph.schedule_graph_update = function(reason)
    calls[#calls + 1] = reason
  end

  MiniTest.expect.equality(true, graph.start_server(0))
  watchfiles.handle { { uri = vim.uri_from_fname "/tmp/changed.md", type = FileChangeType.Changed } }
  MiniTest.expect.equality({}, calls)

  watchfiles.handle { { uri = vim.uri_from_fname "/tmp/created.md", type = FileChangeType.Created } }
  watchfiles.handle { { uri = vim.uri_from_fname "/tmp/deleted.md", type = FileChangeType.Deleted } }
  MiniTest.expect.equality({ "files", "files" }, calls)

  graph.stop_server()
  graph.schedule_graph_update = original_schedule
end

return T
