local new_set, eq, has_error = MiniTest.new_set, MiniTest.expect.equality, MiniTest.expect.error

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

local picker = require "obsidian.picker"
local api = require "obsidian.api"
local Path = require "obsidian.path"
local helpers = require "tests.helpers"

local function with_picker_stubs(stubs, fn)
  local original_get_plugin_info = api.get_plugin_info
  local original_default = package.loaded["obsidian.picker._default"]
  local original_telescope = package.loaded["obsidian.picker._telescope"]

  package.loaded["obsidian.picker._default"] = stubs.default
  package.loaded["obsidian.picker._telescope"] = stubs.telescope

  local ok, err = pcall(fn)

  api.get_plugin_info = original_get_plugin_info
  package.loaded["obsidian.picker._default"] = original_default
  package.loaded["obsidian.picker._telescope"] = original_telescope
  picker.get(false)

  if not ok then
    error(err, 0)
  end
end

T["get defers configured picker availability check until first picker call"] = function()
  local calls = 0
  local invoked = 0

  with_picker_stubs({
    default = {
      select = function()
        invoked = invoked + 1
        return "default"
      end,
    },
  }, function()
    api.get_plugin_info = function(name)
      calls = calls + 1
      eq("telescope.nvim", name)
      return nil
    end

    picker.get "telescope.nvim"
    eq(0, calls)

    eq("default", picker.pick {})
    eq(1, calls)
    eq(1, invoked)

    eq("default", picker.pick {})
    eq(1, calls)
    eq(2, invoked)
  end)
end

T["get lazy-resolves select when it is the first picker call"] = function()
  local calls = 0
  local invoked = 0

  with_picker_stubs({
    default = {
      select = function()
        invoked = invoked + 1
        return "default"
      end,
    },
  }, function()
    api.get_plugin_info = function(name)
      calls = calls + 1
      eq("telescope.nvim", name)
      return nil
    end

    picker.get "telescope.nvim"
    eq(0, calls)

    eq("default", picker.select {})
    eq(1, calls)
    eq(1, invoked)
  end)
end

T["get uses configured picker if it becomes available before first picker call"] = function()
  local available = false
  local calls = 0
  local invoked = 0

  with_picker_stubs({
    telescope = {
      select = function()
        invoked = invoked + 1
        return "telescope"
      end,
    },
  }, function()
    api.get_plugin_info = function(name)
      calls = calls + 1
      eq("telescope.nvim", name)
      if available then
        return { path = "/tmp/telescope.nvim" }
      end
    end

    picker.get "telescope.nvim"
    eq(0, calls)

    available = true
    eq("telescope", picker.pick {})
    eq(1, calls)
    eq(1, invoked)

    available = false
    eq("telescope", picker.pick {})
    eq(1, calls)
    eq(2, invoked)
  end)
end

T["pick_note raises a removal error"] = function()
  has_error(function()
    picker.pick_note()
  end, "picker.pick_note has been removed; use picker.select instead")
end

T["pick passes every selection to the default note opener"] = function()
  local original_select = picker.select
  local picker_util = require "obsidian.picker.util"
  local original_open_notes = picker_util.open_notes
  local first = "/vault/one.md"
  local second = { filename = "/vault/two.md" }
  local opened

  local ok, err = pcall(function()
    picker.select = function(_, _, on_choice)
      on_choice { first, second }
    end
    picker_util.open_notes = function(entries)
      opened = entries
    end

    picker.pick({ first, second }, { allow_multiple = true })
  end)

  picker.select = original_select
  picker_util.open_notes = original_open_notes
  if not ok then
    error(err)
  end

  eq({ first, second }, opened)
end

T["pick preserves varargs for custom multiple-selection callbacks"] = function()
  local original_select = picker.select
  local first = { filename = "/vault/one.md" }
  local second = { filename = "/vault/two.md" }
  local choices

  local ok, err = pcall(function()
    picker.select = function(_, _, on_choice)
      on_choice { first, second }
    end

    picker.pick({ first, second }, {
      allow_multiple = true,
      callback = function(...)
        choices = { ... }
      end,
    })
  end)

  picker.select = original_select
  if not ok then
    error(err)
  end

  eq({ first, second }, choices)
end

T["open_notes opens a single result directly"] = function()
  local picker_util = require "obsidian.picker.util"
  local original_open_note = api.open_note
  local entry = { filename = "/vault/one.md", lnum = 2 }
  local opened

  api.open_note = function(value)
    opened = value
  end
  picker_util.open_notes { entry }
  api.open_note = original_open_note

  eq(entry, opened)
end

T["open_notes sends multiple results to quickfix"] = function()
  local picker_util = require "obsidian.picker.util"
  picker_util.open_notes {
    { filename = "/vault/one.md", lnum = 2, col = 3 },
    { filename = "/vault/one.md", lnum = 4, col = 5 },
  }

  local items = vim.fn.getqflist()
  eq(2, #items)
  eq(vim.fs.normalize "/vault/one.md", vim.fs.normalize(vim.fn.bufname(items[1].bufnr)))
  eq(2, items[1].lnum)
  eq(3, items[1].col)
  eq(vim.fs.normalize "/vault/one.md", vim.fs.normalize(vim.fn.bufname(items[2].bufnr)))
  eq(4, items[2].lnum)
  eq(5, items[2].col)
  vim.cmd "cclose"
end

T["note and tag mappings accept string values"] = function()
  local mappings = require "obsidian.picker.mappings"
  local Note = require "obsidian.note"
  local ui = require "obsidian.ui"
  local original_from_file = Note.from_file
  local original_put = vim.api.nvim_put
  local original_update = ui.update
  local inserted = {}

  local ok, err = pcall(function()
    Note.from_file = function(path)
      eq("/vault/note.md", path)
      return {
        format_link = function()
          return "[[note]]"
        end,
      }
    end
    vim.api.nvim_put = function(lines)
      inserted[#inserted + 1] = lines[1]
    end
    ui.update = function() end

    mappings.insert_link "/vault/note.md"
    mappings.insert_tag "project"
  end)

  Note.from_file = original_from_file
  vim.api.nvim_put = original_put
  ui.update = original_update
  if not ok then
    error(err)
  end

  eq({ "[[note]]", "#project" }, inserted)
end

T["find_files_from_cache applies initial query case-insensitively"] = function()
  local dir = Path.temp { suffix = "-obsidian-picker" }
  dir:mkdir { parents = true }
  helpers.write("# Agenda", dir / "Agenda.md")
  helpers.write("# Other", dir / "Other.md")
  Obsidian = { dir = dir }

  local cache = require "obsidian.cache"
  cache.setup { enabled = true, backend = "memory" }
  vim.wait(1000, function()
    return cache.is_ready()
  end)

  local picked_values
  local picked_opts
  local mapped
  local original_select = picker.select
  picker.select = function(values, opts)
    picked_values = values
    picked_opts = opts
  end

  eq(
    true,
    picker.find_files_from_cache {
      use_cache = true,
      query = "agenda",
      selection_mappings = {
        ["<C-l>"] = {
          desc = "map",
          callback = function(path)
            mapped = path
          end,
        },
      },
    }
  )
  picked_opts.selection_mappings["<C-l>"].callback(picked_values[1])

  local search = require "obsidian.search"
  local original_find_async = search.find_async
  local filesystem_calls = 0
  search.find_async = function()
    filesystem_calls = filesystem_calls + 1
  end
  picker.find_files { use_cache = true, query = "agenda" }
  search.find_async = original_find_async

  picker.select = original_select

  eq(0, filesystem_calls)
  eq(1, #picked_values)
  eq("Agenda", picked_values[1].text)
  eq(true, picked_opts.allow_multiple)
  eq(nil, picked_opts.query)
  eq(tostring(dir / "Agenda.md"), mapped)
  local preview = picked_opts.preview_item(picked_values[1])
  eq({ "# Agenda" }, vim.api.nvim_buf_get_lines(preview.buf, 0, -1, false))
  vim.api.nvim_buf_delete(preview.buf, { force = true })
end

T["find_files presents filesystem paths without a shell command"] = function()
  local dir = Path.temp { suffix = "-obsidian-picker" }
  dir:mkdir { parents = true }
  helpers.write("# A", dir / "a.md")
  helpers.write("# B", dir / "b.md")
  helpers.write("text", dir / "other.txt")
  local resolved_dir = dir:resolve { strict = true }
  local expected_paths = { tostring(resolved_dir / "a.md"), tostring(resolved_dir / "b.md") }
  Obsidian = {
    dir = dir,
    opts = {
      file = { ignore_filters = {} },
      search = { sort_by = "path", sort_reversed = false },
    },
  }

  local picked_values
  local picked_opts
  local selected
  with_picker_stubs({
    telescope = {
      select = function(values, opts, on_choice)
        picked_values = values
        picked_opts = opts
        on_choice(values)
      end,
    },
  }, function()
    api.get_plugin_info = function()
      return { path = "/tmp/telescope.nvim" }
    end
    picker.get "telescope.nvim"
    picker.find_files {
      dir = dir,
      query = "initial",
      callback = function(paths)
        selected = paths
      end,
    }

    vim.wait(1000, function()
      return selected ~= nil
    end)
  end)

  eq(expected_paths, picked_values)
  eq(true, vim.endswith(picked_opts.format_item(picked_values[1]), "a.md"))
  eq(true, vim.endswith(picked_opts.format_item(picked_values[2]), "b.md"))
  eq("initial", picked_opts.query)
  eq(expected_paths, selected)
end

return T
