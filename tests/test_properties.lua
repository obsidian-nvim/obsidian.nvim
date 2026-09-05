local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

local function setup_cache()
  child.lua [[require("obsidian.cache").setup { enabled = true, backend = "memory" }]]
  h.child_wait(child, [[return require("obsidian.cache").is_ready()]], { desc = "cache ready" })
end

---Run the properties picker with the given Lua arguments and capture every
---picker stage, always choosing the first entry to advance the flow.
---
---@param args_lua string
---@return table[]
local function pick_properties(args_lua)
  return h.child_await(
    child,
    ([[
      local picker = require "obsidian.picker"
      local picker_util = require "obsidian.picker.util"
      local original_select = picker.select
      local original_open_notes = picker_util.open_notes
      local captured = {}

      picker.select = function(items, opts, on_choice)
        local entries = {}
        for _, item in ipairs(items) do
          local entry = {
            key = item.key,
            value = item.value,
            count = item.count,
            filename = item.filename,
            text = item.text,
          }
          if opts.format_item then
            entry.formatted = opts.format_item(item)
          end
          entries[#entries + 1] = entry
        end
        captured[#captured + 1] = {
          prompt = opts.prompt,
          entries = entries,
        }
        if #items > 0 then
          on_choice { items[1] }
        end
      end

      picker_util.open_notes = function(entries)
        local opened = {}
        for _, entry in ipairs(entries) do
          opened[#opened + 1] = entry.filename
        end
        captured[#captured + 1] = { opened = opened }
      end

      require("obsidian.commands.properties").pick(%s)

      picker.select = original_select
      picker_util.open_notes = original_open_notes
      done(captured)
    ]]):format(args_lua),
    { desc = "properties picker" }
  )
end

T["pick walks through keys, values, and notes"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["a.md"] = "---\nstatus: done\ntags:\n  - work\n  - personal\n---\n# A",
    ["b.md"] = "---\nstatus: todo\ntags:\n  - work\n---\n# B",
    ["c.md"] = "# C",
  })
  setup_cache()

  local captured = pick_properties "nil, nil"

  eq("Properties", captured[1].prompt)
  eq(2, #captured[1].entries)
  eq("status", captured[1].entries[1].key)
  eq(2, captured[1].entries[1].count)
  eq("tags", captured[1].entries[2].key)
  eq(2, captured[1].entries[2].count)

  eq("Property 'status'", captured[2].prompt)
  eq(2, #captured[2].entries)
  eq("done", captured[2].entries[1].value)
  eq(1, captured[2].entries[1].count)
  eq("todo", captured[2].entries[2].value)
  eq(1, captured[2].entries[2].count)

  eq("Property 'status: done'", captured[3].prompt)
  eq(1, #captured[3].entries)
  eq(vim.fs.normalize(tostring(child.Obsidian.dir / "a.md")), captured[3].entries[1].filename)
  eq("a.md", captured[3].entries[1].text)

  eq({ opened = { vim.fs.normalize(tostring(child.Obsidian.dir / "a.md")) } }, captured[4])
end

T["pick skips top-level YAML sequence keys"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["seq.md"] = "---\n- item1\n- item2\n---\n# Seq",
    ["a.md"] = "---\nstatus: done\n---\n# A",
  })
  setup_cache()

  local captured = pick_properties "nil, nil"

  eq("Properties", captured[1].prompt)
  eq(1, #captured[1].entries)
  eq("status", captured[1].entries[1].key)
end

T["pick with a key starts at its values"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["a.md"] = "---\nstatus: done\n---\n# A",
    ["b.md"] = "---\nstatus: todo\n---\n# B",
  })
  setup_cache()

  local captured = pick_properties [["status", nil]]

  eq("Property 'status'", captured[1].prompt)
  eq(2, #captured[1].entries)
  eq("done", captured[1].entries[1].value)
  eq("todo", captured[1].entries[2].value)
end

T["pick with a key and value starts at matching notes"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["a.md"] = "---\nstatus: done\n---\n# A",
    ["b.md"] = "---\nstatus: todo\n---\n# B",
  })
  setup_cache()

  local captured = pick_properties [["status", "done"]]

  eq("Property 'status: done'", captured[1].prompt)
  eq(1, #captured[1].entries)
  eq(vim.fs.normalize(tostring(child.Obsidian.dir / "a.md")), captured[1].entries[1].filename)
  eq({ opened = { vim.fs.normalize(tostring(child.Obsidian.dir / "a.md")) } }, captured[2])
end

T["pick normalizes quoted, numeric, and boolean value arguments"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["a.md"] = "---\nstatus: done\nnumber: 3\nflag: true\n---\n# A",
  })
  setup_cache()

  local captured = pick_properties [["number", "3"]]
  eq("Property 'number: 3'", captured[1].prompt)

  captured = pick_properties [["flag", "true"]]
  eq("Property 'flag: true'", captured[1].prompt)
end

T["command dispatches to the property picker"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["a.md"] = "---\nstatus: done\n---\n# A",
    ["b.md"] = "---\nstatus: todo\n---\n# B",
  })
  setup_cache()

  local result = h.child_await(
    child,
    [[
      local picker = require "obsidian.picker"
      local captured
      picker.select = function(items, opts)
        captured = { prompt = opts.prompt, count = #items }
      end
      require("obsidian.commands.properties")({ fargs = { "status" } })
      done(captured)
    ]],
    { desc = "properties command" }
  )

  eq("Property 'status'", result.prompt)
  eq(2, result.count)
end

T["cursor_property"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["a.md"] = "---\nstatus: done\ntags:\n  - work\n---\n# A",
  })
  child.cmd("edit " .. files["a.md"])

  child.lua [[vim.api.nvim_win_set_cursor(0, { 2, 1 })]]
  eq({ "status" }, child.lua [[return { require("obsidian.api").cursor_property() }]])

  child.lua [[vim.api.nvim_win_set_cursor(0, { 2, 8 })]]
  eq({ "status", "done" }, child.lua [[return { require("obsidian.api").cursor_property() }]])

  child.lua [[vim.api.nvim_win_set_cursor(0, { 3, 2 })]]
  eq({ "tags" }, child.lua [[return { require("obsidian.api").cursor_property() }]])

  child.lua [[vim.api.nvim_win_set_cursor(0, { 4, 4 })]]
  eq({ "tags", "work" }, child.lua [[return { require("obsidian.api").cursor_property() }]])

  child.lua [[vim.api.nvim_win_set_cursor(0, { 5, 0 })]]
  eq({}, child.lua [[return { require("obsidian.api").cursor_property() }]])
end

T["smart action"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["a.md"] = "---\nstatus: done\n---\n# A",
  })
  child.cmd("edit " .. files["a.md"])

  child.lua [[
    vim.api.nvim_win_set_cursor(0, { 2, 1 })
    _G.smart_action_key = require("obsidian.actions").smart_action()
    vim.api.nvim_win_set_cursor(0, { 2, 8 })
    _G.smart_action_value = require("obsidian.actions").smart_action()
  ]]

  eq(
    "<cmd>lua require('obsidian.commands.properties').pick(\"status\", nil)<cr>",
    child.lua_get [[_G.smart_action_key]]
  )
  eq(
    '<cmd>lua require(\'obsidian.commands.properties\').pick("status", "done")<cr>',
    child.lua_get [[_G.smart_action_value]]
  )
end

return T
