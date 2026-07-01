local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local Path = require "obsidian.path"
local helpers = require "tests.helpers"

local T = new_set {
  hooks = {
    post_case = function()
      pcall(function()
        require("obsidian.cache").shutdown()
      end)
      if Obsidian and Obsidian.dir then
        vim.fn.delete(tostring(Obsidian.dir), "rf")
      end
      Obsidian = nil
      require("obsidian.lsp.watchfiles").reset_handlers()
    end,
  },
}

T["stats"] = new_set()

T["stats"]["collect uses cache rows and computes graph stats"] = function()
  local dir = Path.temp { suffix = "-obsidian-stats" }
  dir:mkdir { parents = true }
  helpers.write(
    table.concat({
      "---",
      "aliases: [Alias A]",
      "tags: [Foo]",
      "---",
      "# A",
      "Hello [[B]] [[Missing]] [Site](https://example.com) [[#Local]]",
      "^block-a",
    }, "\n"),
    dir / "A.md"
  )
  helpers.write("# B", dir / "B.md")
  Obsidian = { dir = dir }

  local cache = require "obsidian.cache"
  cache.setup { enabled = true, backend = "memory" }
  vim.wait(1000, function()
    return cache.is_ready()
  end)

  local Note = require "obsidian.note"
  local original_from_file = Note.from_file
  Note.from_file = function()
    error "stats should use cache"
  end

  local stats = require("obsidian.stats").collect { include_unresolved = true, include_backlinks = true }

  Note.from_file = original_from_file

  eq(2, stats.vault.note_count)
  eq(2, stats.aggregate.links_out)
  eq(1, stats.aggregate.links_resolved)
  eq(1, stats.aggregate.links_unresolved)
  eq(1, stats.aggregate.links_external)
  eq(1, stats.aggregate.links_anchor)
  eq(1, stats.aggregate.backlinks)
  eq(1, stats.aggregate.tags)
  eq("foo", stats.tags[1].tag)
  eq(1, #stats.unresolved_links)
  eq("Missing", stats.unresolved_links[1].location)
end

T["stats"]["collect_async returns a snapshot"] = function()
  local dir = Path.temp { suffix = "-obsidian-stats" }
  dir:mkdir { parents = true }
  helpers.write("# Note", dir / "Note.md")
  Obsidian = { dir = dir }

  local done = false
  local result
  require("obsidian.stats").collect_async({ use_cache = false }, function(stats, err)
    result = { stats = stats, err = err }
    done = true
  end)

  vim.wait(1000, function()
    return done
  end)

  eq(nil, result.err)
  eq(1, result.stats.vault.note_count)
end

return T
