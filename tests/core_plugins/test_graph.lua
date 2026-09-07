local helpers = require "tests.helpers"
local cache = require "obsidian.cache"

local T = helpers.temp_vault

local function start_cache()
  cache.setup { enabled = true, backend = "memory" }
  helpers.wait(function()
    return cache.is_ready()
  end, { desc = "note cache" })
end

T["build_graph uses obsidian.Graph"] = function()
  local graph_view = require "obsidian.core-plugins.graph"
  local nested = Obsidian.dir / "nested"
  nested:mkdir()

  helpers.write("[[B]] [[Missing]]", Obsidian.dir / "A.md")
  helpers.write("---\ntags: [graph]\n---\n# B", nested / "B.md")
  start_cache()

  local data = graph_view.build_graph()
  MiniTest.expect.equality({
    { source = "A", target = "missing:Missing" },
    { source = "A", target = "nested/B" },
    { source = "nested/B", target = "tag:graph" },
  }, data.links)
  MiniTest.expect.equality("note", data.nodes[1].type)
  MiniTest.expect.equality("missing", data.nodes[2].type)
  MiniTest.expect.equality("tag", data.nodes[4].type)
end

T["resolve_graph_arg"] = function()
  local graph = require "obsidian.core-plugins.graph"
  local nested = Obsidian.dir / "nested"
  nested:mkdir()
  local path = nested / "A.md"
  helpers.write("# A", path)

  local scope = graph.resolve_graph_arg(tostring(path))
  MiniTest.expect.equality({ kind = "note", id = "nested/A" }, scope)
  scope = graph.resolve_graph_arg "nested"
  MiniTest.expect.equality({ kind = "folder", folder = "nested" }, scope)

  vim.cmd.edit(vim.fn.fnameescape(tostring(path)))
  scope = graph.resolve_graph_arg "%"
  MiniTest.expect.equality({ kind = "note", id = "nested/A" }, scope)
  vim.cmd "enew"
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
  start_cache()

  MiniTest.expect.equality(tostring(path), graph.note_path_by_id "A")
  MiniTest.expect.equality(nil, graph.note_path_by_id "missing")
end

T["open_note_by_id"] = function()
  local graph = require "obsidian.core-plugins.graph"
  local path = Obsidian.dir / "A.md"
  helpers.write("# A", path)
  start_cache()

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

T["live graph watches cache file changes"] = function()
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
  watchfiles.handle { { uri = vim.uri_from_fname "/tmp/created.md", type = FileChangeType.Created } }
  watchfiles.handle { { uri = vim.uri_from_fname "/tmp/deleted.md", type = FileChangeType.Deleted } }
  MiniTest.expect.equality({ "files", "files", "files" }, calls)

  graph.stop_server()
  graph.schedule_graph_update = original_schedule
end

return T
