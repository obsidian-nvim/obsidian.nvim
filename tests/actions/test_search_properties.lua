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
        key_select = { items = items, prompt = opts.prompt }
        table.sort(key_select.items)
        on_choice { "status" }
        return
      end

      if not value_select then
        value_select = { items = items, prompt = opts.prompt }
        table.sort(value_select.items)
        on_choice { "active" }
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

  eq({ "status", "type" }, result.key_select.items)
  eq("Properties", result.key_select.prompt)
  eq({ "active", "done" }, result.value_select.items)
  eq("status", result.value_select.prompt)
  eq(1, result.note_select.count)
  eq("status: active", result.note_select.prompt)
  eq("a", result.note_select.text)
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

return T
