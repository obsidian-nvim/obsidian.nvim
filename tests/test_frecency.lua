local eq = MiniTest.expect.equality
local h = dofile "tests/helpers.lua"
local frecency = require "obsidian.frecency"
local T, child = h.child_vault()

T["frecency"] = MiniTest.new_set()
T["frecency"]["normalizes each candidate once per sort"] = function()
  local calls = child.lua [[
    local Path = require "obsidian.path"
    local frecency = require "obsidian.frecency"
    local vault = tostring(Obsidian.dir)
    local first = tostring(Obsidian.dir / "First.md")
    local second = tostring(Obsidian.dir / "Second.md")
    frecency.score(first, vault)

    local original_resolve = Path.resolve
    local resolve_calls = 0
    Path.resolve = function(self, opts)
      resolve_calls = resolve_calls + 1
      return original_resolve(self, opts)
    end

    local less = frecency.comparator(vault)
    for _ = 1, 100 do
      less(first, second)
      less(second, first)
    end
    Path.resolve = original_resolve
    return resolve_calls
  ]]

  eq(2, calls)
end

T["frecency"]["weights recent visits and ignores expired visits"] = function()
  local day = 24 * 60 * 60
  local now = 100 * day
  local score, last_visit = frecency._score_visits({ now, now - 2 * day, now - 100 * day }, now)

  eq(170, score)
  eq(now, last_visit)
end

T["frecency"]["records visits with cooldown and sorts by score"] = function()
  local vault = tostring(child.Obsidian.dir)
  local recent = tostring(child.Obsidian.dir / "Recent.md")
  local frequent = tostring(child.Obsidian.dir / "Frequent.md")
  local now = os.time()

  eq(true, child.lua_get(([=[require("obsidian.frecency").record(%q, %q, %d)]=]):format(recent, vault, now - 100)))
  eq(false, child.lua_get(([=[require("obsidian.frecency").record(%q, %q, %d)]=]):format(recent, vault, now - 90)))
  eq(true, child.lua_get(([=[require("obsidian.frecency").record(%q, %q, %d)]=]):format(recent, vault, now)))
  eq(true, child.lua_get(([=[require("obsidian.frecency").record(%q, %q, %d)]=]):format(frequent, vault, now - 50)))

  eq(
    { recent, frequent },
    child.lua_get(([=[
    require("obsidian.frecency").sort_paths({ %q, %q }, %q)
  ]=]):format(frequent, recent, vault))
  )
end

T["frecency"]["persists history independently from metadata cache"] = function()
  local vault = tostring(child.Obsidian.dir)
  local path = tostring(child.Obsidian.dir / "frecency.json")
  local vault_path = vim.fs.normalize(tostring(child.Obsidian.dir / "note.md"))
  local store = frecency._load_store(path, vault)
  store.visits[vault_path] = { os.time() - 100, os.time() - 20 }
  store.dirty = true
  frecency._flush(store)

  local loaded = frecency._load_store(path, vault)
  eq(store.visits[vault_path], loaded.visits[vault_path])
end

T["frecency"]["tracks note buffer entry only when enabled"] = function()
  h.child_mock_vault_contents(child, { ["Disabled.md"] = "# Disabled", ["Enabled.md"] = "# Enabled" })
  local disabled_path = child.lua_get [[ tostring(Obsidian.dir / "Disabled.md") ]]
  local enabled_path = child.lua_get [[ tostring(Obsidian.dir / "Enabled.md") ]]

  child.lua(([=[
    vim.cmd.edit(vim.fn.fnameescape(%q))
    vim.schedule(function() _G.frecency_bufenter_checked = true end)
  ]=]):format(disabled_path))
  h.child_wait(child, [[return _G.frecency_bufenter_checked == true]])

  child.lua [[ assert(package.loaded["obsidian.frecency"] == nil) ]]

  child.lua [[ Obsidian.opts.search.sort_by = "frecency" ]]
  child.lua(([=[vim.cmd.edit(vim.fn.fnameescape(%q))]=]):format(enabled_path))
  h.child_wait(
    child,
    ([=[
    local score = require("obsidian.frecency").score(%q, tostring(Obsidian.dir))
    return score > 0
  ]=]):format(enabled_path)
  )

  eq(
    true,
    child.lua_get(([=[require("obsidian.frecency").score(%q, tostring(Obsidian.dir)) > 0]=]):format(enabled_path))
  )
end

T["frecency"]["sorts uncached filesystem results by visits"] = function()
  local first = tostring(child.Obsidian.dir / "First.md")
  local second = tostring(child.Obsidian.dir / "Second.md")
  vim.fn.writefile({ "# First" }, first)
  vim.fn.writefile({ "# Second" }, second)

  local now = os.time()
  local vault = tostring(child.Obsidian.dir)
  child.lua(([=[
    local f = require("obsidian.frecency")
    f.record(%q, %q, %d)
    f.record(%q, %q, %d)
    f.record(%q, %q, %d)
  ]=]):format(first, vault, now - 1000, first, vault, now - 100, second, vault, now - 200))

  local results = {}
  child.lua(([=[
    require("obsidian.search").find_async(
      %q, nil, { sort_by = "frecency", sort_reversed = true },
      function(path) _G.frecency_results = _G.frecency_results or {}; table.insert(_G.frecency_results, path) end,
      function() _G.frecency_done = true end
    )
  ]=]):format(vault))
  h.child_wait(child, [[return _G.frecency_done == true]])
  results = child.lua_get [[_G.frecency_results]]

  eq(first, results[1])
  eq(second, results[2])
end

T["frecency"]["sorts cached picker entries by visits"] = function()
  h.child_mock_vault_contents(child, { ["First.md"] = "# First", ["Second.md"] = "# Second" })
  h.child_setup_cache(child)

  local entries = child.lua [[
    local picker = require "obsidian.picker"
    local cache = require "obsidian.cache"
    local frecency = require "obsidian.frecency"
    local now = os.time()
    local first = tostring(Obsidian.dir / "First.md")
    local second = tostring(Obsidian.dir / "Second.md")
    frecency.record(first, tostring(Obsidian.dir), now - 1000)
    frecency.record(first, tostring(Obsidian.dir), now - 100)
    frecency.record(second, tostring(Obsidian.dir), now - 200)
    Obsidian.opts.search.sort_by = "frecency"

    local selected
    local original = picker.select
    picker.select = function(values)
      selected = values
    end
    cache.find_files()
    picker.select = original
    return selected
  ]]

  eq("First", entries[1].text)
  eq("Second", entries[2].text)
end

return T
