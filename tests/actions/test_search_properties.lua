local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

T["search_properties opens a three-stage picker over frontmatter"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["a.md"] = "---\ntype: note\nstatus: active\n---\n# A",
    ["b.md"] = "---\ntype: note\nstatus: done\n---\n# B",
  })

  local result = h.child_await(
    child,
    [[
    local picker = require "obsidian.picker"
    local key_select, value_select

    picker.select = function(items, opts, on_choice)
      if not key_select then
        key_select = { items = vim.tbl_map(opts.format_item, items), prompt = opts.prompt }
        on_choice { items[1] }
        return
      end

      if not value_select then
        value_select = { items = vim.tbl_map(opts.format_item, items), prompt = opts.prompt }
        on_choice { items[1] }
        return
      end

      done {
        key_select = key_select,
        value_select = value_select,
        note_select = {
          count = #items,
          prompt = opts.prompt,
          text = items[1].text,
        },
      }
    end

    require("obsidian.actions").search_properties()
  ]],
    { desc = "search_properties picker" }
  )

  eq({ "status (2)", "type (2)" }, result.key_select.items)
  eq("Properties", result.key_select.prompt)
  eq({ "active (1)", "done (1)" }, result.value_select.items)
  eq("status", result.value_select.prompt)
  eq(1, result.note_select.count)
  eq("status: active", result.note_select.prompt)
  eq("a", result.note_select.text)
end

T["search_properties uses the cache when enabled, without scanning the filesystem"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["a.md"] = "---\ntype: note\nstatus: active\n---\n# A",
    ["b.md"] = "---\ntype: note\nstatus: done\n---\n# B",
  })

  local result = h.child_await(
    child,
    [[
    local cache = require "obsidian.cache"
    cache.setup { enabled = true, backend = "memory" }
    vim.wait(1000, function()
      return cache.is_ready()
    end)

    local search = require "obsidian.search"
    local filesystem_calls = 0
    search.find_async = function()
      filesystem_calls = filesystem_calls + 1
    end

    local picker = require "obsidian.picker"
    local key_select, value_select

    picker.select = function(items, opts, on_choice)
      if not key_select then
        key_select = { items = vim.tbl_map(opts.format_item, items), prompt = opts.prompt }
        on_choice { items[1] }
        return
      end

      if not value_select then
        value_select = { items = vim.tbl_map(opts.format_item, items), prompt = opts.prompt }
        on_choice { items[1] }
        return
      end

      done {
        key_select = key_select,
        value_select = value_select,
        note_select = {
          count = #items,
          prompt = opts.prompt,
          text = items[1].text,
        },
        filesystem_calls = filesystem_calls,
      }
    end

    require("obsidian.actions").search_properties()
  ]],
    { desc = "search_properties picker (cache-enabled)" }
  )

  eq({ "status (2)", "type (2)" }, result.key_select.items)
  eq("Properties", result.key_select.prompt)
  eq({ "active (1)", "done (1)" }, result.value_select.items)
  eq("status", result.value_select.prompt)
  eq(1, result.note_select.count)
  eq("status: active", result.note_select.prompt)
  eq("a", result.note_select.text)
  eq(0, result.filesystem_calls)
end

T["search_properties KEY VALUE skips straight to matching notes"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["a.md"] = "---\ntype: note\nstatus: active\n---\n# A",
    ["b.md"] = "---\ntype: note\nstatus: done\n---\n# B",
  })

  local result = h.child_await(
    child,
    [[
    local picker = require "obsidian.picker"

    picker.select = function(items, opts, on_choice)
      done { count = #items, prompt = opts.prompt, text = items[1].text }
    end

    require("obsidian.actions").search_properties("status", "done")
  ]],
    { desc = "search_properties KEY VALUE picker" }
  )

  eq(1, result.count)
  eq("status: done", result.prompt)
  eq("b", result.text)
end

for name, setup in pairs {
  ["without the cache"] = "",
  ["with the cache"] = [[
    local cache = require "obsidian.cache"
    cache.setup { enabled = true, backend = "memory" }
    vim.wait(1000, function()
      return cache.is_ready()
    end)
  ]],
} do
  T["search_properties includes id, aliases and tags " .. name] = function()
    h.mock_vault_contents(child.Obsidian.dir, {
      ["a.md"] = "---\nid: custom-id\naliases: [alpha]\ntags: [one]\n---\n# A",
      ["b.md"] = "---\nstatus: done\n---\n# B",
    })

    local result = h.child_await(child, setup .. [[
      local picker = require "obsidian.picker"
      picker.select = function(items)
        done(vim.tbl_map(function(item)
          return item.name
        end, items))
      end

      require("obsidian.actions").search_properties()
    ]], { desc = "search_properties restored keys" })

    eq({ "aliases", "id", "status", "tags" }, result)
  end
end

T["properties command joins a value containing spaces"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["a.md"] = "---\nstatus: in progress\n---\n# A",
    ["b.md"] = "---\nstatus: done\n---\n# B",
  })

  local result = h.child_await(
    child,
    [[
    local picker = require "obsidian.picker"

    picker.select = function(items, opts)
      done { count = #items, prompt = opts.prompt, text = items[1].text }
    end

    require("obsidian.commands.properties") { fargs = { "status", "in", "progress" } }
  ]],
    { desc = "properties command with spaced value" }
  )

  eq(1, result.count)
  eq("status: in progress", result.prompt)
  eq("a", result.text)
end

T["search_properties counts the notes carrying each key and value"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["a.md"] = "---\ntype: note\ntags: [x, x]\n---\n# A",
    ["b.md"] = "---\ntype: note\ntags: [x, y]\n---\n# B",
    ["c.md"] = "---\ntype: idea\n---\n# C",
  })

  local result = h.child_await(
    child,
    [[
    local picker = require "obsidian.picker"
    local key_labels
    picker.select = function(items, opts, on_choice)
      local labels = vim.tbl_map(opts.format_item, items)
      if not key_labels then
        key_labels = labels
        on_choice { items[2] }
        return
      end
      done { keys = key_labels, values = labels }
    end

    require("obsidian.actions").search_properties()
  ]],
    { desc = "search_properties counts" }
  )

  eq({ "tags (2)", "type (3)" }, result.keys)
  eq({ "idea (1)", "note (2)" }, result.values)
end

return T
