local PickerSearch = require "obsidian.picker.search"
local Ui = require "obsidian.picker._ui"

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["grep uses the Obsidian query engine and preserves grep callbacks"] = function()
  local documents = {
    PickerSearch.from_lines("/vault/work.md", { "# Work", "needle here", "#work" }, { root = "/vault" }),
    PickerSearch.from_lines("/vault/home.md", { "# Home", "nothing here" }, { root = "/vault" }),
  }

  local original_index_async = PickerSearch.index_async
  local original_pick = Ui.pick
  local pick_values
  local pick_opts
  local callback_entries
  local mapped_path

  local ok, err = pcall(function()
    PickerSearch.index_async = function(dir, opts, callback)
      eq("/vault", tostring(dir))
      eq({}, opts)
      callback(documents)
      return function() end
    end
    Ui.pick = function(values, opts)
      pick_values = values
      pick_opts = opts
    end

    Ui.grep {
      dir = "/vault",
      query = "content:needle",
      callback = function(entries)
        callback_entries = entries
      end,
      selection_mappings = {
        ["<C-l>"] = {
          desc = "insert link",
          callback = function(path)
            mapped_path = path
          end,
        },
      },
    }

    eq(2, #pick_values)
    eq("Search", pick_opts.prompt_title)
    eq("content:needle", pick_opts.query)

    local picker_items = vim.tbl_map(function(entry)
      return { entry = entry, display = entry.text }
    end, pick_values)
    local matches = pick_opts.search("content:needle", picker_items)
    eq(1, #matches)
    eq("work.md:2  needle here", matches[1].display)
    eq(2, matches[1].entry.lnum)
    eq(1, matches[1].entry.col)

    pick_opts.selection_mappings["<C-l>"].callback(matches[1].entry)
    eq("/vault/work.md", mapped_path)

    pick_opts.callback(matches[1].entry)
    eq(
      {
        {
          filename = "/vault/work.md",
          lnum = 2,
          col = 1,
          text = "needle here",
        },
      },
      callback_entries
    )
  end)

  PickerSearch.index_async = original_index_async
  Ui.pick = original_pick
  if not ok then
    error(err, 0)
  end
end

T["the ui picker dispatches search to its builtin grep implementation"] = function()
  local picker = require "obsidian.picker"
  local original_grep = Ui.grep
  local received

  local ok, err = pcall(function()
    Ui.grep = function(opts)
      received = opts
    end
    picker.get "ui"
    picker.grep { query = "tag:#work" }
    eq("tag:#work", received.query)
  end)

  Ui.grep = original_grep
  picker.get(false)
  if not ok then
    error(err, 0)
  end
end

return T
