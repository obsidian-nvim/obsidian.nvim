local eq = MiniTest.expect.equality
local helpers = require "tests.helpers"
local Path = require "obsidian.path"

local T = MiniTest.new_set {
  hooks = {
    pre_case = function()
      local dir = Path.temp { suffix = "-obsidian-graph" }
      dir:mkdir { parents = true }
      require("obsidian").setup {
        legacy_commands = false,
        workspaces = { { path = tostring(dir) } },
        cache = { enabled = false },
      }
      local cache = require "obsidian.cache"
      cache.setup { enabled = true, backend = "memory" }
      helpers.wait(function()
        return cache.is_ready()
      end, { desc = "note cache" })
    end,
    post_case = function()
      require("obsidian.cache").shutdown()
      vim.fn.delete(tostring(Obsidian.dir), "rf")
    end,
  },
}

local function put(rel_path, row)
  row.path = tostring(Obsidian.dir / rel_path)
  require("obsidian.cache").notes.upsert(row)
  return row.path
end

T["builds note graph and cache-only diagnostics"] = function()
  local a = put("A.md", {
    links_out = {
      { kind = "wiki", raw = "[[Project B]]", target = "Project B", line = 1, col = 1 },
      { kind = "wiki", raw = "[[Missing]]", target = "Missing", line = 2, col = 1 },
      { kind = "markdown", raw = "[site](https://example.com)", target = "https://example.com", line = 3, col = 1 },
      { kind = "wiki", raw = "![[image.png]]", target = "image.png", line = 4, col = 1 },
    },
  })
  local b = put("nested/B.md", {
    id = "project-b",
    aliases = { "Project B" },
    properties = { title = "Better B" },
  })
  local orphan = put("Orphan.md", {})

  local graph = require("obsidian.graph").from_cache()
  local result = graph:to_table()

  eq({
    {
      id = "A",
      type = "note",
      title = "A",
      path = a,
      folder = "",
      aliases = {},
      tags = {},
      exists = true,
    },
    {
      id = "missing:Missing",
      type = "missing",
      title = "Missing",
      folder = "",
      aliases = {},
      tags = {},
      exists = false,
    },
    {
      id = "Orphan",
      type = "note",
      title = "Orphan",
      path = orphan,
      folder = "",
      aliases = {},
      tags = {},
      exists = true,
    },
    {
      id = "nested/B",
      type = "note",
      title = "Better B",
      path = b,
      folder = "nested",
      aliases = { "Project B" },
      tags = {},
      exists = true,
    },
  }, result.nodes)
  eq({
    { source = "A", target = "missing:Missing" },
    { source = "A", target = "nested/B" },
  }, result.links)
  eq({
    {
      source = "A",
      path = a,
      target = "Missing",
      kind = "wiki",
      raw = "[[Missing]]",
      line = 2,
      col = 1,
    },
  }, graph:broken_links())
  eq({ orphan }, graph:orphan_files())
end

T["resolves relative markdown links"] = function()
  local a = put("nested/A.md", {
    links_out = { { kind = "markdown", target = "../B.md" } },
  })
  local b = put("B.md", {})

  local graph = require("obsidian.graph").from_cache()
  local result = graph:to_table()

  eq({ { source = "nested/A", target = "B" } }, result.links)
  eq({}, graph:broken_links())
  eq({}, graph:orphan_files())
  eq(a, result.nodes[2].path)
  eq(b, result.nodes[1].path)
end

T["optionally includes tag nodes without changing orphans"] = function()
  local tagged = put("Tagged.md", { tags = { "graph", "#health" } })
  local plain = put("Plain.md", {})
  local graph = require("obsidian.graph").from_cache()

  local without_tags = graph:to_table()
  eq(2, #without_tags.nodes)
  eq({}, without_tags.links)
  eq({ plain, tagged }, graph:orphan_files())

  local with_tags = graph:to_table { include_tag_nodes = true }
  eq({
    { source = "Tagged", target = "tag:graph" },
    { source = "Tagged", target = "tag:health" },
  }, with_tags.links)
  eq("tag", with_tags.nodes[3].type)
  eq("tag", with_tags.nodes[4].type)
  eq({ plain, tagged }, graph:orphan_files())
end

T["is an immutable cache snapshot"] = function()
  local row = { links_out = { { kind = "wiki", target = "Missing" } } }
  local first = put("First.md", row)
  local graph = require("obsidian.graph").from_cache()

  row.links_out[1].target = "Changed"
  put("Later.md", {})

  eq("Missing", graph:broken_links()[1].target)
  eq({ first }, graph:orphan_files())
  eq(2, #graph:to_table().nodes)
  eq(3, #require("obsidian.graph").from_cache():to_table().nodes)
end

return T
