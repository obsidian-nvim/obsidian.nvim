local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

T["search_tags uses select for tag choice"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["a.md"] = "#alpha",
    ["b.md"] = "#alpha/nested\n#beta",
  })

  local result = h.child_await(
    child,
    [[
    local picker = require "obsidian.picker"
    local tag_select

    picker.select = function(items, opts, on_choice)
      if type(items[1]) == "string" then
        table.sort(items)
        tag_select = {
          items = items,
          prompt = opts.prompt,
          allow_multiple = opts.allow_multiple,
          has_selection_mappings = opts.selection_mappings ~= nil,
        }
        on_choice { "alpha" }
        return
      end

      local preview = opts.preview_item(items[1])
      done {
        tag_select = tag_select,
        result_select = {
          count = #items,
          prompt = opts.prompt,
          formatted = opts.format_item(items[1]),
          display = items[1].display,
          preview_pos = preview.pos,
          preview_line = vim.api.nvim_buf_get_lines(preview.buf, preview.pos[1] - 1, preview.pos[1], false)[1],
        },
      }
    end

    require("obsidian.actions").search_tags()
  ]],
    { desc = "search_tags picker" }
  )

  eq({ "alpha", "alpha/nested", "beta" }, result.tag_select.items)
  eq(nil, result.tag_select.prompt)
  eq(true, result.tag_select.allow_multiple)
  eq(true, result.tag_select.has_selection_mappings)
  eq(2, result.result_select.count)
  eq("#alpha", result.result_select.prompt)
  eq(result.result_select.display, result.result_select.formatted)
  eq({ 1, 0 }, result.result_select.preview_pos)
  eq(true, vim.startswith(result.result_select.preview_line, "#alpha"))
end

return T
