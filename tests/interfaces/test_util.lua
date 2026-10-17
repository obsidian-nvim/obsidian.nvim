local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

T["selection filters cancellation and merges mapping overrides"] = function()
  local result = h.child_await(
    child,
    [[
    local picker = require "obsidian.picker"
    local util = require "obsidian.interfaces.util"
    local selected
    picker.select = function(values, opts, callback)
      _G.picker_opts = opts
      callback({})
      callback({ values[1], values[2] })
    end
    util.select({ "one", "two" }, {
      prompt = "Default",
      selection_mappings = {
        ["<C-a>"] = { desc = "default" },
        ["<C-b>"] = { desc = "keep" },
      },
    }, {
      prompt = "Override",
      selection_mappings = {
        ["<C-a>"] = false,
        ["<C-c>"] = { desc = "custom" },
      },
    }, function(choices)
      selected = choices
    end)
    local opts = _G.picker_opts
    done {
      prompt = opts.prompt,
      a = opts.selection_mappings["<C-a>"] ~= nil,
      b = opts.selection_mappings["<C-b>"].desc,
      c = opts.selection_mappings["<C-c>"].desc,
      selected = selected,
    }
  ]],
    { desc = "selector success and mapping merge" }
  )

  eq("Override", result.prompt)
  eq(false, result.a)
  eq("keep", result.b)
  eq("custom", result.c)
  eq({ "one", "two" }, result.selected)
end

T["quickfix export preserves payload, ranges, title, and history"] = function()
  local result = h.child_await(
    child,
    [=[
    local picker_util = require "obsidian.picker.util"
    local Range = require "obsidian.range"
    local path = tostring(Obsidian.dir / "note.md")
    vim.fn.writefile({ "abcdef" }, path)
    vim.fn.setqflist({}, " ", { title = "Previous list", items = { { filename = path, lnum = 1 } } })
    local payload = { source = "domain" }
    picker_util.send_to_qf({
      { filename = path, text = "Location", range = Range.new(0, 2, 0, 5), user_data = payload },
      { text = "not a file" },
      "ordinary string",
    }, { title = "New results" })
    local current = vim.fn.getqflist({ title = 1, items = 1, nr = 0 })
    local previous = vim.fn.getqflist({ title = 1, nr = current.nr - 1 })
    local item = current.items[1]
    done {
      current = {
        title = current.title,
        items = { {
          filename = item.filename or vim.api.nvim_buf_get_name(item.bufnr),
          lnum = item.lnum,
          col = item.col,
          end_lnum = item.end_lnum,
          end_col = item.end_col,
          text = item.text,
          user_data = item.user_data,
        } },
      },
      previous = previous,
    }
    vim.cmd.cclose()
  ]=],
    { desc = "quickfix export and history" }
  )

  local root = child.lua_get [[tostring(Obsidian.dir)]]
  eq("New results", result.current.title)
  eq(1, #result.current.items)
  eq({
    filename = vim.fs.joinpath(root, "note.md"),
    lnum = 1,
    col = 3,
    end_lnum = 1,
    end_col = 6,
    text = "Location",
    user_data = { source = "domain" },
  }, result.current.items[1])
  eq("Previous list", result.previous.title)
end

T["no_default_mappings keeps only per-call mappings"] = function()
  local result = h.child_await(
    child,
    [[
    local util = require "obsidian.interfaces.util"
    local opts = util.picker_options({
      selection_mappings = { x = { desc = "default" } },
    }, {
      no_default_mappings = true,
      selection_mappings = { y = { desc = "custom" } },
    })
    done {
      x = opts.selection_mappings.x ~= nil,
      y = opts.selection_mappings.y.desc,
    }
  ]],
    { desc = "selector default mapping opt-out" }
  )

  eq(false, result.x)
  eq("custom", result.y)
end

return T
