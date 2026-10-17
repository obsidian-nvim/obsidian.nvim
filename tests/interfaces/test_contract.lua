local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

T["folder selection is single-select and returns a complete entry"] = function()
  local root = tostring(child.lua_get [[tostring(Obsidian.dir)]])
  local result = child.lua(string.format(
    [=[
    local picker = require "obsidian.picker"
    local original = picker.select
    picker.select = function(items, opts, callback)
      _G.picker_opts = opts
      _G.folder_items = items
      callback({ items[1], items[2] })
    end
    local selected
    require("obsidian.interfaces.folders").pick({ workspace_dir = %q }, function(choices)
      selected = choices
    end)
    picker.select = original
    return {
      selected_count = #selected,
      selected = selected[1],
      multiple = picker_opts.allow_multiple,
      displayed = picker_opts.format_item(folder_items[1]),
    }
  ]=],
    root
  ))

  eq(1, result.selected_count)
  eq(root, result.selected.filename)
  eq("/", result.selected.text)
  eq(false, result.multiple)
  eq("/", result.displayed)
end

T["headings browse by default, while cancellation has no side effects"] = function()
  local result = h.child_await(
    child,
    [[
    local picker = require "obsidian.picker"
    local api = require "obsidian.api"
    local log = require "obsidian.log"
    local original_select = picker.select
    local original_open = api.open_note
    local original_warn = log.warn
    local path = tostring(Obsidian.dir / "heading.md")
    vim.api.nvim_buf_set_name(0, path)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "# Heading" })
    local opened, warnings = 0, 0
    api.open_note = function(entry)
      opened = opened + 1
      _G.opened_entry = entry
    end
    log.warn = function()
      warnings = warnings + 1
    end

    picker.select = function(items, _, on_choice)
      on_choice({ items[1] })
    end
    require("obsidian.interfaces.headings").open()
    picker.select = function(_, _, on_choice)
      on_choice({})
    end
    require("obsidian.interfaces.headings").open()

    picker.select = original_select
    api.open_note = original_open
    log.warn = original_warn
    done { opened = opened, warnings = warnings, filename = opened_entry.filename }
  ]],
    { desc = "heading default and cancellation" }
  )

  eq(1, result.opened)
  eq(0, result.warnings)
  eq(vim.fs.joinpath(child.lua_get [[tostring(Obsidian.dir)]], "heading.md"), result.filename)
end

T["template acquisition preserves prompt and enforces one path"] = function()
  local root = tostring(child.lua_get [[tostring(Obsidian.dir)]])
  local dir = vim.fs.joinpath(root, "templates")
  vim.fn.mkdir(dir, "p")

  local result = child.lua(string.format(
    [=[
    local picker = require "obsidian.picker"
    local original = picker.find_files
    picker.find_files = function(opts)
      _G.find_files_opts = opts
      opts.callback({ "first.md", "second.md" })
    end
    local selected
    require("obsidian.interfaces.templates").pick({
      dir = %q,
      picker = { prompt = "Choose template" },
    }, function(paths)
      selected = paths
    end)
    picker.find_files = original
    return {
      selected = selected,
      prompt = find_files_opts.prompt_title,
      allow_multiple = find_files_opts.allow_multiple,
      no_default_mappings = find_files_opts.no_default_mappings,
    }
  ]=],
    dir
  ))

  eq({ "first.md" }, result.selected)
  eq("Choose template", result.prompt)
  eq(false, result.allow_multiple)
  eq(true, result.no_default_mappings)
end

return T
