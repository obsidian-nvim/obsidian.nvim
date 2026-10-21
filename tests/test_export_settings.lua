local eq = MiniTest.expect.equality
local child = MiniTest.new_child_neovim()
local root

local T = MiniTest.new_set {
  hooks = {
    pre_case = function()
      root = vim.fn.tempname()
      vim.fn.mkdir(root, "p")
      child.restart { "-u", "scripts/minimal_init.lua", "-i", "NONE" }
      child.lua(
        [[
        _G.vault = ...
        _G.write_config = function(name, data, profile)
          local dir = vim.fs.joinpath(vault, profile or ".obsidian")
          vim.fn.mkdir(dir, "p")
          vim.fn.writefile({ vim.json.encode(data) }, vim.fs.joinpath(dir, name))
        end
        _G.read_config = function(name, profile)
          return vim.json.decode(table.concat(vim.fn.readfile(vim.fs.joinpath(vault, profile or ".obsidian", name)), "\n"))
        end
        _G.configure = function(extra)
          require("obsidian").setup(vim.tbl_deep_extend("force", {
            legacy_commands = false,
            workspaces = { { path = vault, strict = true } },
            ui = { enable = false }, footer = { enabled = false },
            frontmatter = { enabled = false }, log_level = vim.log.levels.ERROR,
            new_notes_location = "notes_subdir", notes_subdir = "Lua notes",
            templates = { folder = "Templates", date_format = "DD-MM-YYYY", time_format = "HH:mm:ss" },
            daily_notes = { folder = "Daily", date_format = "DD-MM-YYYY", template = "daily" },
            unique_note = { enabled = false, folder = "Unique", format = "YYYYMMDDHHmmss", template = "unique" },
            attachments = { folder = "Images" },
            link = { style = "markdown", format = "relative", auto_update = true },
          }, extra or {}))
        end
        _G.export = function()
          return require("obsidian.config.export").write(Obsidian.workspace)
        end
        _G.warnings, _G.errors = {}, {}
        require("obsidian.log").warn = function(...) table.insert(warnings, { ... }) end
        require("obsidian.log").err = function(...) table.insert(errors, { ... }) end
        configure()
        dofile "plugin/obsidian.lua"
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

T["a Lua-only vault writes all supported app settings on request"] = function()
  eq(0, child.lua_get 'vim.fn.isdirectory(vim.fs.joinpath(vault, ".obsidian"))')
  child.lua "_G.paths = export()"
  eq(5, child.lua_get "#paths")
  eq({
    newFileLocation = "folder",
    newFileFolderPath = "Lua notes",
    attachmentFolderPath = "Images",
    useMarkdownLinks = true,
    newLinkFormat = "relative",
    alwaysUpdateLinks = true,
  }, child.lua_get 'read_config("app.json")')
  eq(
    { folder = "Templates", dateFormat = "DD-MM-YYYY", timeFormat = "HH:mm:ss" },
    child.lua_get 'read_config("templates.json")'
  )
  eq(
    { folder = "Daily", format = "DD-MM-YYYY", template = "Templates/daily.md" },
    child.lua_get 'read_config("daily-notes.json")'
  )
  eq(
    { folder = "Unique", format = "YYYYMMDDHHmmss", template = "Templates/unique.md" },
    child.lua_get 'read_config("zk-prefixer.json")'
  )
  eq(
    { templates = true, ["daily-notes"] = true, ["zk-prefixer"] = false },
    child.lua_get 'read_config("core-plugins.json")'
  )
end

T["the command exports Lua overrides instead of imported app options and reloads"] = function()
  child.lua [[
    write_config("app.json", { newFileLocation = "folder", newFileFolderPath = "App notes", attachmentFolderPath = "App images" })
    write_config("templates.json", { folder = "App templates", dateFormat = "YYYY", timeFormat = "HH" })
    configure { workspaces = { { path = vault, strict = true, overrides = {
      notes_subdir = "Workspace notes", templates = { folder = "Workspace templates" },
    } } } }
    assert(Obsidian.opts.notes_subdir == "App notes")
    vim.cmd "Obsidian export_settings"
  ]]
  eq("Workspace notes", child.lua_get 'read_config("app.json").newFileFolderPath')
  eq("Workspace templates", child.lua_get 'read_config("templates.json").folder')
  eq("DD-MM-YYYY", child.lua_get 'read_config("templates.json").dateFormat')
  eq("Workspace notes", child.lua_get "Obsidian.opts.notes_subdir")
  eq("Workspace templates", child.lua_get "Obsidian.opts.templates.folder")
  eq(0, child.lua_get "#errors")
end

T["unrelated settings survive repeated exports"] = function()
  child.lua [[
    write_config("app.json", { vimMode = true, pdfExportSettings = { pageSize = "Letter" }, custom = vim.NIL })
    write_config("templates.json", { custom = { "one", "two" } })
    write_config("daily-notes.json", { autorun = true })
    write_config("zk-prefixer.json", { custom = 42 })
    write_config("core-plugins.json", { graph = true, canvas = false, custom = { enabled = true } })
    export()
    export()
  ]]
  eq(true, child.lua_get 'read_config("app.json").vimMode')
  eq({ pageSize = "Letter" }, child.lua_get 'read_config("app.json").pdfExportSettings')
  eq(vim.NIL, child.lua_get 'read_config("app.json").custom')
  eq({ "one", "two" }, child.lua_get 'read_config("templates.json").custom')
  eq(true, child.lua_get 'read_config("daily-notes.json").autorun')
  eq(42, child.lua_get 'read_config("zk-prefixer.json").custom')
  eq({
    graph = true,
    canvas = false,
    custom = { enabled = true },
    templates = true,
    ["daily-notes"] = true,
    ["zk-prefixer"] = false,
  }, child.lua_get 'read_config("core-plugins.json")')
end

T["legacy core-plugin arrays preserve unrelated enabled plugins"] = function()
  child.lua [[
    write_config("core-plugins.json", { "graph", "zk-prefixer", "canvas", "templates" })
    configure { templates = { enabled = false }, unique_note = { enabled = true } }
    export()
    export()
    _G.core = read_config("core-plugins.json")
    table.sort(core)
  ]]
  eq({ "canvas", "daily-notes", "graph", "zk-prefixer" }, child.lua_get "core")
end

T["empty legacy arrays remain arrays when all mapped plugins are disabled"] = function()
  child.lua [[
    write_config("core-plugins.json", {})
    configure { templates = { enabled = false }, daily_notes = { enabled = false }, unique_note = { enabled = false } }
    export()
  ]]
  eq({ "[]" }, child.lua_get 'vim.fn.readfile(vim.fs.joinpath(vault, ".obsidian/core-plugins.json"))')
end

T["UTF-8 BOM files keep their unrelated values"] = function()
  child.lua [[
    write_config("app.json", {})
    vim.fn.writefile({ string.char(239, 187, 191) .. '{"custom":42}' }, vim.fs.joinpath(vault, ".obsidian/app.json"))
    export()
  ]]
  eq(42, child.lua_get 'read_config("app.json").custom')
end

T["root note and daily folders round-trip without inheriting another folder"] = function()
  child.lua [[
    configure { notes_subdir = "Notes", daily_notes = { folder = "" }, unique_note = { folder = "" } }
    export()
    _G.shared = require("obsidian.config.app_settings").read(vault)
  ]]
  eq("/", child.lua_get 'read_config("daily-notes.json").folder')
  eq("/", child.lua_get 'read_config("zk-prefixer.json").folder')
  eq("", child.lua_get "shared.daily_notes.folder")
  eq("", child.lua_get "shared.unique_note.folder")
  child.lua "configure { notes_subdir = vim.NIL }; export()"
  eq("root", child.lua_get 'read_config("app.json").newFileLocation')
end

T["daily note folders keep the same location after export"] = MiniTest.new_set {
  parametrize = {
    { false, "Notes", "Notes", "Notes", "notes_subdir" },
    { "", "Notes", "/", "", "notes_subdir" },
    { "Daily", "Notes", "Daily", "Daily", "notes_subdir" },
    { false, false, "/", "", "notes_subdir" },
    { false, "Notes", "Notes", "Notes", "current_dir" },
  },
}
T["daily note folders keep the same location after export"]["uses the effective Lua folder"] = function(
  daily_folder,
  notes_subdir,
  exported,
  resolved,
  location
)
  child.lua(
    [[
    local daily_folder, notes_subdir, location = ...
    configure {
      notes_subdir = notes_subdir or vim.NIL,
      new_notes_location = location,
      daily_notes = { folder = daily_folder or vim.NIL },
    }
    _G.before = tostring(require("obsidian.daily").daily_note_path(1700000000))
    vim.cmd "Obsidian export_settings"
    _G.after = tostring(require("obsidian.daily").daily_note_path(1700000000))
  ]],
    { daily_folder, notes_subdir, location }
  )
  eq(exported, child.lua_get 'read_config("daily-notes.json").folder')
  eq(resolved, child.lua_get "Obsidian.opts.daily_notes.folder")
  eq(child.lua_get "before", child.lua_get "after")
end

T["current-folder mode is exported explicitly"] = function()
  child.lua 'configure { new_notes_location = "current_dir" }; export()'
  eq("current", child.lua_get 'read_config("app.json").newFileLocation')
end

T["attachment path modes survive export and import"] = MiniTest.new_set {
  parametrize = {
    { "/", "", "/" },
    { ".", ".", "." },
    { "./images", "./images", "./images" },
    { ".images", ".images", ".images" },
  },
}
T["attachment path modes survive export and import"]["retains the path meaning"] = function(folder, imported, exported)
  child.lua("configure { attachments = { folder = ... } }; export()", { folder })
  eq(exported, child.lua_get 'read_config("app.json").attachmentFolderPath')
  eq(imported, child.lua_get 'require("obsidian.config.app_settings").read(vault).attachments.folder')
end

T["absolute vault paths become portable paths without using the working directory"] = function()
  child.lua [[
    configure {
      templates = { folder = vim.fs.joinpath(vault, "Templates") },
      daily_notes = { template = vim.fs.joinpath(vault, "Other/Daily.md") },
      unique_note = { template = "unique" },
      attachments = { folder = vim.fs.joinpath(vault, "Media") },
    }
    export()
  ]]
  eq("Templates", child.lua_get 'read_config("templates.json").folder')
  eq("Other/Daily.md", child.lua_get 'read_config("daily-notes.json").template')
  eq("Templates/unique.md", child.lua_get 'read_config("zk-prefixer.json").template')
  eq("Media", child.lua_get 'read_config("app.json").attachmentFolderPath')
end

T["cleared templates replace old app selections with empty strings"] = function()
  child.lua [[
    write_config("daily-notes.json", { template = "Old" })
    write_config("zk-prefixer.json", { template = "Old" })
    configure { templates = { folder = vim.NIL }, daily_notes = { template = vim.NIL }, unique_note = { template = vim.NIL } }
    export()
  ]]
  eq("", child.lua_get 'read_config("templates.json").folder')
  eq("", child.lua_get 'read_config("daily-notes.json").template')
  eq("", child.lua_get 'read_config("zk-prefixer.json").template')
end

T["workspace profiles and export destinations remain isolated"] = function()
  child.lua [[
    local second = vim.fs.joinpath(vault, "second")
    vim.fn.mkdir(second, "p")
    configure { workspaces = {
      { path = vault, name = "first", strict = true },
      { path = second, name = "second", strict = true, overrides = { app_settings = { config_dir = ".obsidian-work" }, notes_subdir = "Second notes" } },
    } }
    require("obsidian.workspace").set "second"
    export()
    _G.second_app = vim.json.decode(table.concat(vim.fn.readfile(vim.fs.joinpath(second, ".obsidian-work/app.json")), "\n"))
  ]]
  eq("Second notes", child.lua_get "second_app.newFileFolderPath")
  eq(0, child.lua_get 'vim.fn.isdirectory(vim.fs.joinpath(vault, ".obsidian"))')
  eq(0, child.lua_get 'vim.fn.isdirectory(vim.fs.joinpath(vault, "second/.obsidian"))')
end

T["malformed settings stop the export before any destination is changed"] = MiniTest.new_set {
  parametrize = { { "{ invalid" }, { "[]" }, { "null" } },
}
T["malformed settings stop the export before any destination is changed"]["preserves existing bytes"] = function(text)
  child.lua(
    [[
    write_config("app.json", { untouched = true })
    vim.fn.writefile({ ... }, vim.fs.joinpath(vault, ".obsidian/zk-prefixer.json"))
    _G.before = vim.fn.readfile(vim.fs.joinpath(vault, ".obsidian/app.json"))
    _G.success, _G.failure = pcall(export)
  ]],
    { text }
  )
  eq(false, child.lua_get "success")
  eq(true, child.lua_get 'failure:find("zk-prefixer.json", 1, true) ~= nil')
  eq(true, child.lua_get 'vim.deep_equal(before, vim.fn.readfile(vim.fs.joinpath(vault, ".obsidian/app.json")))')
  eq(0, child.lua_get 'vim.fn.filereadable(vim.fs.joinpath(vault, ".obsidian/templates.json"))')
end

T["unsupported Lua values fail before creating app settings"] = MiniTest.new_set {
  parametrize = {
    { 'unique_note = { format = function() error("must not run") end }', "unique_note.format" },
    { 'daily_notes = { date_format = "%d-%m-%Y" }', "daily_notes.date_format" },
    { 'templates = { time_format = "%H:%M" }', "templates.time_format" },
    { 'templates = { date_format = "" }', "templates.date_format" },
    { 'templates = { folder = "." }', "templates.folder" },
    { 'attachments = { folder = "../outside" }', "attachments.folder" },
    { 'attachments = { folder = "./../outside" }', "attachments.folder" },
    { 'daily_notes = { template = "../../outside" }', "daily_notes.template" },
  },
}
T["unsupported Lua values fail before creating app settings"]["reports the field"] = function(options, field)
  child.lua("configure { " .. options .. " }; _G.success, _G.failure = pcall(export)")
  eq(false, child.lua_get "success")
  eq(true, child.lua_get(("failure:find(%q, 1, true) ~= nil"):format(field)))
  eq(0, child.lua_get 'vim.fn.isdirectory(vim.fs.joinpath(vault, ".obsidian"))')
end

T["Lua-only rules are not serialized or executed"] = function()
  child.lua [[
    local fail = function() error("must not run") end
    configure { note_id_func = fail, frontmatter = { func = fail }, templates = {
      customizations = { daily = { notes_subdir = "Personal", note_id_func = fail } },
      substitutions = { custom = fail },
    } }
    export()
  ]]
  eq(0, child.lua_get 'vim.fn.filereadable(vim.fs.joinpath(vault, ".obsidian/nvim.json"))')
  eq(vim.NIL, child.lua_get 'read_config("templates.json").customizations')
end

T["an unreadable file is not mistaken for a missing file"] = function()
  child.lua [[
    write_config("app.json", { untouched = true })
    local open = io.open
    io.open = function(path, mode)
      if vim.endswith(path, "/app.json") and mode == "r" then return nil, "permission denied" end
      return open(path, mode)
    end
    _G.success, _G.failure = pcall(export)
    io.open = open
  ]]
  eq(false, child.lua_get "success")
  eq(true, child.lua_get 'failure:find("permission denied", 1, true) ~= nil')
  eq(true, child.lua_get 'read_config("app.json").untouched')
end

T["a staging failure keeps all destination files and removes temporary files"] = function()
  child.lua [[
    write_config("app.json", { untouched = true })
    local write = vim.uv.fs_write
    local calls = 0
    vim.uv.fs_write = function(...)
      calls = calls + 1
      if calls == 2 then return nil, "disk full" end
      return write(...)
    end
    _G.success, _G.failure = pcall(export)
    vim.uv.fs_write = write
    _G.remaining = vim.fn.glob(vim.fs.joinpath(vault, ".obsidian/*"), false, true)
  ]]
  eq(false, child.lua_get "success")
  eq(true, child.lua_get 'failure:find("disk full", 1, true) ~= nil')
  eq(true, child.lua_get 'read_config("app.json").untouched')
  eq(1, child.lua_get "#remaining")
end

T["replacement errors are reported and remaining temporary files are removed"] = function()
  child.lua [[
    write_config("app.json", { untouched = true })
    local rename = vim.uv.fs_rename
    vim.uv.fs_rename = function() return nil, "permission denied" end
    _G.success, _G.failure = pcall(export)
    vim.uv.fs_rename = rename
    _G.remaining = vim.fn.glob(vim.fs.joinpath(vault, ".obsidian/*"), false, true)
  ]]
  eq(false, child.lua_get "success")
  eq(true, child.lua_get 'failure:find("Unable to replace", 1, true) ~= nil')
  eq(true, child.lua_get 'read_config("app.json").untouched')
  eq(1, child.lua_get "#remaining")
end

T["the command reports export errors without reloading the workspace"] = function()
  child.lua [[
    write_config("templates.json", { "invalid" })
    local set = require("obsidian.workspace").set
    require("obsidian.workspace").set = function() error("must not reload") end
    vim.cmd "Obsidian export_settings"
    require("obsidian.workspace").set = set
  ]]
  eq(1, child.lua_get "#errors")
  eq(0, child.lua_get 'vim.fn.filereadable(vim.fs.joinpath(vault, ".obsidian/app.json"))')
end

T["the command is available outside notes even when core features are disabled"] = function()
  child.lua "configure { templates = { enabled = false }, daily_notes = { enabled = false }, unique_note = { enabled = false } }"
  eq(
    true,
    child.lua_get 'vim.list_contains(require("obsidian.commands").get_completions("", "Obsidian ", 9), "export_settings")'
  )
  child.lua 'Obsidian.workspace = nil; vim.cmd "Obsidian export_settings"'
  eq(1, child.lua_get "#errors")
  eq(0, child.lua_get 'vim.fn.isdirectory(vim.fs.joinpath(vault, ".obsidian"))')
end

T["exported template paths identify the actual Markdown files"] = MiniTest.new_set {
  parametrize = {
    { "daily", "daily.md", "unique", "unique.md" },
    { "daily.md", "daily.md", "unique.md", "unique.md" },
    { "daily.v1", "daily.v1.md", "unique.v2", "unique.v2.md" },
  },
}
T["exported template paths identify the actual Markdown files"]["pass an exact file lookup"] = function(
  daily,
  daily_file,
  unique,
  unique_file
)
  child.lua(
    [[
    local daily, daily_file, unique, unique_file = ...
    local templates = vim.fs.joinpath(vault, "Templates")
    vim.fn.writefile({ "# Daily template" }, vim.fs.joinpath(templates, daily_file))
    vim.fn.writefile({ "# Unique template" }, vim.fs.joinpath(templates, unique_file))
    configure { daily_notes = { template = daily }, unique_note = { template = unique } }
    export()
  ]],
    { daily, daily_file, unique, unique_file }
  )
  eq("Templates/" .. daily_file, child.lua_get 'read_config("daily-notes.json").template')
  eq("Templates/" .. unique_file, child.lua_get 'read_config("zk-prefixer.json").template')
  eq(1, child.lua_get 'vim.fn.filereadable(vim.fs.joinpath(vault, read_config("daily-notes.json").template))')
  eq(1, child.lua_get 'vim.fn.filereadable(vim.fs.joinpath(vault, read_config("zk-prefixer.json").template))')
end

T["generated settings reload and create daily and unique notes from the templates"] = function()
  child.lua [[
    vim.fn.mkdir(vim.fs.joinpath(vault, "Unique"), "p")
    vim.fn.writefile({ "# Daily template" }, vim.fs.joinpath(vault, "Templates/daily.md"))
    vim.fn.writefile({ "# Unique template" }, vim.fs.joinpath(vault, "Templates/unique.md"))
    configure { unique_note = { enabled = true } }
    vim.cmd "Obsidian export_settings"
    _G.daily_note = require("obsidian.daily").today():write()
    _G.unique_note = require("obsidian.unique").new_unique_note()
  ]]
  eq({ "# Daily template" }, child.lua_get "vim.fn.readfile(tostring(daily_note.path))")
  eq({ "# Unique template" }, child.lua_get "vim.fn.readfile(tostring(unique_note.path))")
end

return T
