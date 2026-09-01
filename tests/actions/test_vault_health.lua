local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

T["vault health actions limit results to opts.dir"] = function()
  local root = child.Obsidian.dir
  local scope = root / "scope"
  scope:mkdir { parents = true }

  local scoped_empty = scope / "empty.md"
  local scoped_orphan = scope / "orphan.md"
  local scoped_broken = scope / "broken.md"
  local outside_empty = root / "empty.md"
  local outside_orphan = root / "orphan.md"
  local outside_broken = root / "broken.md"

  h.write("", scoped_empty)
  h.write("orphan", scoped_orphan)
  h.write("[[missing]]", scoped_broken)
  h.write("", outside_empty)
  h.write("orphan", outside_orphan)
  h.write("[[missing]]", outside_broken)

  child.lua [[
    local cache = require "obsidian.cache"
    cache.setup { enabled = true, backend = "memory" }
    assert(vim.wait(1000, cache.is_ready), "cache did not become ready")
  ]]

  local result = child.lua(
    ([=[
    local selected = {}
    require("obsidian.picker").select = function(items, opts)
      selected[opts.prompt] = items
    end

    local original_graph = package.loaded["obsidian.graph"]
    package.loaded["obsidian.graph"] = {
      from_cache = function()
        return {
          orphan_files = function()
            return { %q, %q }
          end,
          broken_links = function()
            return {
              { path = %q, line = 1, col = 1, raw = "[[missing]]" },
              { path = %q, line = 1, col = 1, raw = "[[missing]]" },
            }
          end,
        }
      end,
    }

    local actions = require "obsidian.actions"
    actions.list_empty_notes { dir = "scope" }
    actions.list_orphan_files { dir = %q }
    actions.list_broken_links { dir = "scope" }
    package.loaded["obsidian.graph"] = original_graph

    local result = {}
    for prompt, items in pairs(selected) do
      result[prompt] = vim.tbl_map(function(item)
        return item.filename
      end, items)
    end
    return result
  ]=]):format(
      tostring(scoped_orphan),
      tostring(outside_orphan),
      tostring(scoped_broken),
      tostring(outside_broken),
      tostring(scope)
    )
  )

  eq({ tostring(scoped_empty) }, result["Empty Notes"])
  eq({ tostring(scoped_orphan) }, result["Orphan Files"])
  eq({ tostring(scoped_broken) }, result["Broken Links"])
end

T["graph health actions wait for cache readiness"] = function()
  local result = child.lua [[
    local cache = require "obsidian.cache"
    local picker_called = false
    require("obsidian.picker").select = function()
      picker_called = true
    end

    local original_graph = package.loaded["obsidian.graph"]
    package.loaded["obsidian.graph"] = {
      from_cache = function()
        return { broken_links = function() return {} end }
      end,
    }

    cache.setup { enabled = true, backend = "memory" }
    require("obsidian.actions").list_broken_links()
    local called_before_ready = picker_called
    assert(vim.wait(1000, function() return picker_called end), "action did not run after cache became ready")
    package.loaded["obsidian.graph"] = original_graph

    return { before = called_before_ready, after = picker_called }
  ]]

  eq({ before = false, after = true }, result)
end

T["graph health actions stop cleanly when the cache is disabled"] = function()
  local result = child.lua [[
    local picker_called = false
    require("obsidian.picker").select = function()
      picker_called = true
    end

    local log = require "obsidian.log"
    local warnings = {}
    local original_warn = log.warn
    log.warn = function(message)
      warnings[#warnings + 1] = message
    end

    local actions = require "obsidian.actions"
    actions.list_orphan_files()
    actions.list_broken_links()
    log.warn = original_warn

    return { picker_called = picker_called, warnings = warnings }
  ]]

  eq(false, result.picker_called)
  eq({
    "Orphan and broken-link checks require the note cache; set `cache.enabled = true`",
    "Orphan and broken-link checks require the note cache; set `cache.enabled = true`",
  }, result.warnings)
end

return T
