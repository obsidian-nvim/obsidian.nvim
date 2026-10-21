local eq = MiniTest.expect.equality
local child = MiniTest.new_child_neovim()
local root

local T = MiniTest.new_set {
  hooks = {
    pre_case = function()
      root = vim.fn.tempname()
      vim.fn.mkdir(root, "p")
      vim.fn.writefile(vim.fn.readfile "examples/vault.lua", vim.fs.joinpath(root, ".nvim.lua"))
      child.restart { "-u", "scripts/minimal_init.lua", "-i", "NONE" }
      child.lua(
        [[
        _G.vault = ...
        local date, time = os.date, os.time
        local timestamp = os.time { year = 2026, month = 10, day = 17, hour = 14, min = 30, sec = 0 }
        os.date = function(format, value) return date(format, value or timestamp) end
        os.time = function(value) return value and time(value) or timestamp end
        local templates = vim.fs.joinpath(vault, "Templates")
        vim.fn.mkdir(templates, "p")
        for _, name in ipairs { "daily-plan", "plain" } do
          vim.fn.writefile({ "# {{title}}", "{{date}} {{time}}" }, vim.fs.joinpath(templates, name .. ".md"))
        end
        _G.reload = function()
          vim.cmd("source " .. vim.fn.fnameescape(vim.fs.joinpath(vault, ".nvim.lua")))
        end
        reload()
        -- Exercise the optional-name prompt used by the new-note action.
        require("obsidian.api").input = function() return "" end
        _G.create_note = function(id, template)
          id = id or nil
          template = template or nil
          local callback = function(note) _G.created = note end
          if template then
            require("obsidian.actions").new_from_template(id, template, callback)
          else
            require("obsidian.actions").new(id, callback)
          end
        end
        _G.write_app = function(data)
          vim.fn.mkdir(vim.fs.joinpath(vault, ".obsidian"), "p")
          vim.fn.writefile({ vim.json.encode(data) }, vim.fs.joinpath(vault, ".obsidian/app.json"))
          reload()
        end
      ]],
        { root }
      )
    end,
    post_case = function()
      child.stop()
      vim.fn.delete(root, "rf")
    end,
  },
}

T["local Lua rules create notes with manual and automatic names"] = MiniTest.new_set {
  parametrize = {
    { "Manual note", false, "Notes/Manual note.md" },
    { false, false, "Notes/17-10-2026-14-30.md" },
    { "Manual note", "plain", "Notes/Manual note.md" },
    { "", "plain", "Notes/17-10-2026-14-30.md" },
    { "Manual note", "daily-plan", "Personal/Schedule Daily/SD - 17-10-2026.md" },
    { "", "daily-plan", "Personal/Schedule Daily/SD - 17-10-2026.md" },
  },
}
T["local Lua rules create notes with manual and automatic names"]["writes the expected file"] = function(
  id,
  template,
  path
)
  child.lua("create_note(...)", { id, template })
  eq(true, child.lua_get(("tostring(created.path) == vim.fs.joinpath(vault, %q)"):format(path)))
  eq(1, child.lua_get(("vim.fn.filereadable(vim.fs.joinpath(vault, %q))"):format(path)))
  eq(0, child.lua_get 'vim.fn.isdirectory(vim.fs.joinpath(vault, ".obsidian"))')
end

T["plain template substitutions use the manual title and local date formats"] = function()
  child.lua 'create_note("Manual note", "plain")'
  eq({ "# Manual note", "17-10-2026 14:30" }, child.lua_get "vim.fn.readfile(tostring(created.path))")
end

T["the template picker applies the same rule when the optional title is empty"] = function()
  child.lua [[
    require("obsidian.picker").find_files = function(opts)
      opts.callback { vim.fs.joinpath(vault, "Templates/daily-plan.md") }
    end
    require("obsidian.actions").new_from_template(nil, nil, function(note) _G.created = note end)
  ]]
  eq(
    true,
    child.lua_get 'tostring(created.path) == vim.fs.joinpath(vault, "Personal/Schedule Daily/SD - 17-10-2026.md")'
  )
  eq(1, child.lua_get "vim.fn.filereadable(tostring(created.path))")
end

T["a default note template uses its customization for ordinary new-note actions"] = function()
  child.lua [[
    Obsidian.opts.note.template = "daily-plan"
    create_note("Manual title")
  ]]
  eq(
    true,
    child.lua_get 'tostring(created.path) == vim.fs.joinpath(vault, "Personal/Schedule Daily/SD - 17-10-2026.md")'
  )
end

T["an explicit path overrides both the ordinary and template folders"] = function()
  child.lua 'create_note("Chosen/Manual note")'
  eq(true, child.lua_get 'tostring(created.path) == vim.fs.joinpath(vault, "Chosen/Manual note.md")')
  child.lua 'create_note("Chosen/Manual note", "daily-plan")'
  eq(true, child.lua_get 'tostring(created.path) == vim.fs.joinpath(vault, "Chosen/SD - 17-10-2026.md")')
end

T["a folder-only customization inherits the global naming function"] = function()
  child.lua [[
    Obsidian.opts.templates.customizations.plain = { notes_subdir = "Projects" }
    create_note("Manual note", "plain")
  ]]
  eq(true, child.lua_get 'tostring(created.path) == vim.fs.joinpath(vault, "Projects/Manual note.md")')
  child.lua 'create_note("", "plain")'
  eq(true, child.lua_get 'tostring(created.path) == vim.fs.joinpath(vault, "Projects/17-10-2026-14-30.md")')
end

T["app folders take priority while Lua template rules remain available"] = function()
  child.lua [[
    write_app { newFileLocation = "folder", newFileFolderPath = "Shared notes" }
    create_note("Plain", "plain")
  ]]
  eq(true, child.lua_get 'tostring(created.path) == vim.fs.joinpath(vault, "Shared notes/Plain.md")')
  child.lua 'create_note("Custom", "daily-plan")'
  eq(
    true,
    child.lua_get 'tostring(created.path) == vim.fs.joinpath(vault, "Personal/Schedule Daily/SD - 17-10-2026.md")'
  )
end

T["an app file without a note folder applies the app default"] = function()
  child.lua [[
    write_app(vim.empty_dict())
    create_note("Manual note")
  ]]
  eq(true, child.lua_get 'tostring(created.path) == vim.fs.joinpath(vault, "Manual note.md")')
end

T["reloading the open local config preserves its vault root"] = MiniTest.new_set {
  parametrize = { { "source" }, { "source %" }, { "luafile %" } },
}
T["reloading the open local config preserves its vault root"]["applies the edited options"] = function(command)
  child.lua [[
    vim.cmd("edit " .. vim.fn.fnameescape(vim.fs.joinpath(vault, ".nvim.lua")))
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, line in ipairs(lines) do
      lines[i] = line:gsub('notes_subdir = "Notes"', 'notes_subdir = "Reloaded notes"')
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.cmd "write"
  ]]
  child.cmd(command)
  child.cmd(command)
  eq(child.lua_get "vim.fs.normalize(vault)", child.lua_get "vim.fs.normalize(tostring(Obsidian.dir))")
  eq("Reloaded notes", child.lua_get "Obsidian.opts.notes_subdir")
  child.lua 'create_note("After reload")'
  eq(true, child.lua_get 'tostring(created.path) == vim.fs.joinpath(vault, "Reloaded notes/After reload.md")')
  eq(1, child.lua_get "vim.fn.filereadable(tostring(created.path))")
end

return T
