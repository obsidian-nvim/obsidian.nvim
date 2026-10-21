local h = dofile "tests/helpers.lua"
local eq = MiniTest.expect.equality
local child = MiniTest.new_child_neovim()
local root

local T = MiniTest.new_set {
  hooks = {
    pre_case = function()
      root = vim.fn.tempname()
      assert(root ~= "", "Could not allocate a test directory")
      vim.fn.mkdir(root, "p")
      root = vim.fs.normalize(assert(vim.uv.fs_realpath(root)))
      child.restart { "-u", "scripts/minimal_init.lua", "-i", "NONE" }
      child.lua(
        [[
        local root = ...
        _G.vault_a = vim.fs.joinpath(root, "a")
        _G.vault_b = vim.fs.joinpath(root, "b")
        for _, dir in ipairs { vault_a, vault_b } do vim.fn.mkdir(dir, "p") end
        _G.write_config = function(vault, name, data, dir)
          local folder = vim.fs.joinpath(vault, dir or ".obsidian")
          vim.fn.mkdir(folder, "p")
          vim.fn.writefile({ vim.json.encode(data) }, vim.fs.joinpath(folder, name))
        end
        _G.configure = function(extra)
          return require("obsidian").setup(vim.tbl_deep_extend("force", {
            legacy_commands = false,
            workspaces = { { path = vault_a } },
            log_level = vim.log.levels.ERROR,
            ui = { enable = false }, footer = { enabled = false },
            frontmatter = { enabled = false },
            notes_subdir = "lua-notes", new_notes_location = "current_dir",
            attachments = { folder = "lua-images" },
            templates = {
              folder = "lua-templates", date_format = "YYYY", time_format = "HH:mm:ss",
              substitutions = { custom = function() return "custom" end },
              customizations = { special = { notes_subdir = "special-notes", note_id_func = function() return "special" end } },
            },
            daily_notes = { folder = "lua-daily", date_format = "YYYY", template = "lua-daily-template", default_tags = { "personal" } },
            unique_note = { folder = "lua-unique", format = function() return "custom-id" end, template = "lua-unique-template" },
            link = { style = "markdown", format = "absolute", auto_update = true },
            note_id_func = function(title) return title end,
          }, extra or {}))
        end
        vim.cmd "filetype on"
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

T["Lua-only vaults retain all options and create no app settings"] = function()
  child.lua "configure()"
  eq("lua-images", child.lua_get "Obsidian.opts.attachments.folder")
  eq("lua-templates", child.lua_get "Obsidian.opts.templates.folder")
  eq("HH:mm:ss", child.lua_get "Obsidian.opts.templates.time_format")
  eq("lua-daily-template", child.lua_get "Obsidian.opts.daily_notes.template")
  eq("function", child.lua_get "type(Obsidian.opts.unique_note.format)")
  eq(0, child.lua_get 'vim.fn.isdirectory(vim.fs.joinpath(vault_a, ".obsidian"))')
end

T["all supported explicit app values override global and workspace Lua options"] = function()
  child.lua [[
    write_config(vault_a, "app.json", {
      newFileLocation = "folder", newFileFolderPath = "Notes",
      attachmentFolderPath = "Media", useMarkdownLinks = true,
      newLinkFormat = "relative", alwaysUpdateLinks = true,
      userIgnoreFilters = { "/not-a-gitignore/" },
    })
    write_config(vault_a, "templates.json", { folder = "Templates", dateFormat = "DD.MM.YYYY", timeFormat = "HH.mm" })
    write_config(vault_a, "daily-notes.json", { folder = "Daily", format = "YYYY/MM/DD", template = "Other/Daily", autorun = true })
    write_config(vault_a, "zk-prefixer.json", { folder = "Unique", format = "YYYYMMDDHHmmss", template = "Other/Unique" })
    write_config(vault_a, "core-plugins.json", { templates = true, ["daily-notes"] = true, ["zk-prefixer"] = true })
    configure { workspaces = { { path = vault_a, overrides = {
      notes_subdir = "override-notes", attachments = { folder = "override-media" },
      templates = { folder = "override-templates", time_format = "HH" },
      daily_notes = { date_format = "DD" }, unique_note = { format = "YY" },
      link = { style = "wiki", format = "shortest", auto_update = false },
    } } }, file = { ignore_filters = { "personal/*" } } }
  ]]
  eq("notes_subdir", child.lua_get "Obsidian.opts.new_notes_location")
  eq("Notes", child.lua_get "Obsidian.opts.notes_subdir")
  eq("Media", child.lua_get "Obsidian.opts.attachments.folder")
  eq("Templates", child.lua_get "Obsidian.opts.templates.folder")
  eq("DD.MM.YYYY", child.lua_get "Obsidian.opts.templates.date_format")
  eq("HH.mm", child.lua_get "Obsidian.opts.templates.time_format")
  eq("Daily", child.lua_get "Obsidian.opts.daily_notes.folder")
  eq("YYYY/MM/DD", child.lua_get "Obsidian.opts.daily_notes.date_format")
  eq(true, child.lua_get 'Obsidian.opts.daily_notes.template == vim.fs.joinpath(vault_a, "Other/Daily")')
  eq("Unique", child.lua_get "Obsidian.opts.unique_note.folder")
  eq("YYYYMMDDHHmmss", child.lua_get "Obsidian.opts.unique_note.format")
  eq(true, child.lua_get 'Obsidian.opts.unique_note.template == vim.fs.joinpath(vault_a, "Other/Unique")')
  eq(
    { "markdown", "relative", true },
    child.lua_get "{ Obsidian.opts.link.style, Obsidian.opts.link.format, Obsidian.opts.link.auto_update }"
  )
  eq("special-notes", child.lua_get "Obsidian.opts.templates.customizations.special.notes_subdir")
  eq("custom", child.lua_get "Obsidian.opts.templates.substitutions.custom()")
  eq({ "personal" }, child.lua_get "Obsidian.opts.daily_notes.default_tags")
  eq({ "personal/*" }, child.lua_get "Obsidian.opts.file.ignore_filters")
end

T["empty app.json applies app defaults only to its shared fields"] = function()
  child.lua [[write_config(vault_a, "app.json", vim.empty_dict()); configure()]]
  eq("", child.lua_get "Obsidian.opts.notes_subdir")
  eq("notes_subdir", child.lua_get "Obsidian.opts.new_notes_location")
  eq("", child.lua_get "Obsidian.opts.attachments.folder")
  eq(
    { "wiki", "shortest", false },
    child.lua_get "{ Obsidian.opts.link.style, Obsidian.opts.link.format, Obsidian.opts.link.auto_update }"
  )
  eq("HH:mm:ss", child.lua_get "Obsidian.opts.templates.time_format")
  eq("lua-daily", child.lua_get "Obsidian.opts.daily_notes.folder")
end

T["empty templates.json clears the Lua folder and applies format defaults"] = function()
  child.lua [[write_config(vault_a, "templates.json", vim.empty_dict()); configure()]]
  eq(vim.NIL, child.lua_get "Obsidian.opts.templates.folder")
  eq("YYYY-MM-DD", child.lua_get "Obsidian.opts.templates.date_format")
  eq("HH:mm", child.lua_get "Obsidian.opts.templates.time_format")
  eq("custom", child.lua_get "Obsidian.opts.templates.substitutions.custom()")
end

T["empty daily and unique files use app defaults instead of Lua"] = function()
  child.lua [[
    write_config(vault_a, "daily-notes.json", vim.empty_dict())
    write_config(vault_a, "zk-prefixer.json", vim.empty_dict())
    configure()
  ]]
  eq("", child.lua_get "Obsidian.opts.daily_notes.folder")
  eq("YYYY-MM-DD", child.lua_get "Obsidian.opts.daily_notes.date_format")
  eq(vim.NIL, child.lua_get "Obsidian.opts.daily_notes.template")
  eq("", child.lua_get "Obsidian.opts.unique_note.folder")
  eq("YYYYMMDDHHmm", child.lua_get "Obsidian.opts.unique_note.format")
  eq(vim.NIL, child.lua_get "Obsidian.opts.unique_note.template")
  eq("lua-notes", child.lua_get "Obsidian.opts.notes_subdir")
end

T["empty daily and unique folders follow the app new-note folder"] = function()
  child.lua [[
    write_config(vault_a, "app.json", { newFileLocation = "folder", newFileFolderPath = "Inbox" })
    write_config(vault_a, "daily-notes.json", { folder = "", format = "", template = "" })
    write_config(vault_a, "zk-prefixer.json", { folder = "", format = "", template = "" })
    write_config(vault_a, "templates.json", { folder = "", dateFormat = "", timeFormat = "" })
    configure()
  ]]
  eq("Inbox", child.lua_get "Obsidian.opts.daily_notes.folder")
  eq("Inbox", child.lua_get "Obsidian.opts.unique_note.folder")
  eq("YYYY-MM-DD", child.lua_get "Obsidian.opts.daily_notes.date_format")
  eq("HH:mm", child.lua_get "Obsidian.opts.templates.time_format")
end

T["core plugin state"] = MiniTest.new_set {
  parametrize = {
    { vim.empty_dict(), { true, true, false } },
    { {}, { false, false, false } },
    { { "templates", "zk-prefixer" }, { true, false, true } },
    { { templates = false, ["zk-prefixer"] = true }, { false, true, true } },
  },
}
T["core plugin state"]["supports modern objects and legacy arrays"] = function(data, expected)
  child.lua([[write_config(vault_a, "core-plugins.json", ...); configure()]], { data })
  eq(
    expected,
    child.lua_get "{ Obsidian.opts.templates.enabled, Obsidian.opts.daily_notes.enabled, Obsidian.opts.unique_note.enabled }"
  )
end

T["attachment paths"] = MiniTest.new_set {
  parametrize = {
    { "/", "photo.png" },
    { ".", "nested/photo.png" },
    { "./", "nested/photo.png" },
    { "./assets", "nested/assets/photo.png" },
    { "assets", "assets/photo.png" },
    { ".assets", ".assets/photo.png" },
  },
}
T["attachment paths"]["resolve relative to the vault or target note"] = function(folder, expected)
  child.lua([[write_config(vault_a, "app.json", { attachmentFolderPath = ... }); configure()]], { folder })
  child.lua [[
    local file = vim.fs.joinpath(vault_a, "nested/note.md")
    _G.destination = require("obsidian.attachment").destination_path("photo.png", file)
  ]]
  eq(true, child.lua_get(string.format("destination == vim.fs.joinpath(vault_a, %q)", expected)))
end

T["current-folder mode works with root-level daily notes"] = function()
  child.lua [[
    write_config(vault_a, "app.json", { newFileLocation = "current" })
    write_config(vault_a, "daily-notes.json", vim.empty_dict())
    configure()
    vim.fn.mkdir(vim.fs.joinpath(vault_a, "nested"), "p")
    local source = vim.fs.joinpath(vault_a, "nested/note.md")
    vim.fn.writefile({ "# Source" }, source)
    _G.created = require("obsidian.note").create { id = "New", source_path = source }
  ]]
  eq(true, child.lua_get 'tostring(created.path) == vim.fs.joinpath(vault_a, "nested/New.md")')
end

T["foreign workspaces and switching use each vault's app settings"] = function()
  child.lua [[
    write_config(vault_a, "templates.json", { folder = "A", timeFormat = "HH" })
    write_config(vault_b, "templates.json", { folder = "B", timeFormat = "HH:mm" })
    configure { workspaces = { { name = "A", path = vault_a }, { name = "B", path = vault_b } } }
    _G.foreign = require("obsidian.api")._workspace_opts(Obsidian.workspaces[2])
  ]]
  eq("A", child.lua_get "Obsidian.opts.templates.folder")
  eq("B", child.lua_get "foreign.templates.folder")
  child.lua [[require("obsidian.workspace").set("B")]]
  eq("B", child.lua_get "Obsidian.opts.templates.folder")
  child.lua [[
    vim.fn.delete(vim.fs.joinpath(vault_b, ".obsidian/templates.json"))
    require("obsidian.workspace").set("A")
    require("obsidian.workspace").set("B")
  ]]
  eq("lua-templates", child.lua_get "Obsidian.opts.templates.folder")
  eq("HH:mm:ss", child.lua_get "Obsidian.opts.templates.time_format")
end

T["app paths and formats are used when creating a daily note"] = function()
  child.lua [[
    vim.fn.mkdir(vim.fs.joinpath(vault_a, "Other"), "p")
    vim.fn.writefile({ "# From app template" }, vim.fs.joinpath(vault_a, "Other/Daily.md"))
    write_config(vault_a, "templates.json", { folder = "Templates" })
    write_config(vault_a, "daily-notes.json", { folder = "Diary", format = "YYYY/MM/DD", template = "Other/Daily" })
    configure()
    _G.daily = require("obsidian.daily").daily { date = os.time { year = 2026, month = 10, day = 14, hour = 12 } }
    daily:write()
  ]]
  eq(true, child.lua_get 'tostring(daily.path) == vim.fs.joinpath(vault_a, "Diary/2026/10/14.md")')
  eq({ "# From app template" }, child.lua_get "vim.fn.readfile(tostring(daily.path))")
end

T["malformed files warn and do not block other settings"] = function()
  child.lua [[
    _G.warnings = {}
    require("obsidian.log").warn_once = function(...) table.insert(warnings, { ... }) end
    write_config(vault_a, "templates.json", { folder = "App" })
    vim.fn.writefile({ "{ invalid" }, vim.fs.joinpath(vault_a, ".obsidian/app.json"))
    configure()
  ]]
  eq("lua-images", child.lua_get "Obsidian.opts.attachments.folder")
  eq("App", child.lua_get "Obsidian.opts.templates.folder")
  eq(1, child.lua_get "#warnings")
end

T["invalid field values use app defaults and preserve unrelated Lua options"] = function()
  child.lua [[
    _G.warnings = {}
    require("obsidian.log").warn_once = function(...) table.insert(warnings, { ... }) end
    write_config(vault_a, "app.json", {
      newFileLocation = "wrong", attachmentFolderPath = "../outside",
      useMarkdownLinks = "invalid", newLinkFormat = "wrong", alwaysUpdateLinks = {},
    })
    write_config(vault_a, "templates.json", { folder = {}, dateFormat = false, timeFormat = {} })
    configure()
  ]]
  eq("", child.lua_get "Obsidian.opts.attachments.folder")
  eq("wiki", child.lua_get "Obsidian.opts.link.style")
  eq(false, child.lua_get "Obsidian.opts.link.auto_update")
  eq("HH:mm", child.lua_get "Obsidian.opts.templates.time_format")
  eq(true, child.lua_get "#warnings >= 8")
end

T["custom config directories work for workspaces inside the vault"] = function()
  child.lua [[
    write_config(vault_a, "templates.json", { folder = "Profile" }, ".obsidian-profile")
    vim.fn.mkdir(vim.fs.joinpath(vault_a, "nested"), "p")
    configure {
      app_settings = { config_dir = ".obsidian-profile" },
      workspaces = { { path = vim.fs.joinpath(vault_a, "nested") } },
    }
  ]]
  eq(true, child.lua_get "tostring(Obsidian.dir) == vault_a")
  eq("Profile", child.lua_get "Obsidian.opts.templates.folder")
end

T["only JSON objects are accepted for app settings"] = function()
  child.lua [[
    require("obsidian.log").warn_once = function() end
    write_config(vault_a, "templates.json", { "invalid" })
    configure()
  ]]
  eq("lua-templates", child.lua_get "Obsidian.opts.templates.folder")
end

T["reading preserves the original files byte for byte"] = function()
  child.lua [[
    local dir = vim.fs.joinpath(vault_a, ".obsidian")
    vim.fn.mkdir(dir, "p")
    local file = vim.fs.joinpath(dir, "app.json")
    local lines = { "{", '  "attachmentFolderPath": "Images",', '  "unknown": 42', "}" }
    vim.fn.writefile(lines, file)
    configure()
    _G.unchanged = vim.deep_equal(lines, vim.fn.readfile(file))
  ]]
  eq(true, child.lua_get "unchanged")
end

T["invalid config directory names fail validation"] = function()
  for _, dir in ipairs { ".", "..", "../outside", "relative", "C:/outside" } do
    local success = child.lua_get(
      string.format('pcall(require("obsidian.config").normalize, { app_settings = { config_dir = %q } })', dir)
    )
    eq(false, success)
  end
end

T["repeated setup reloads app settings for an already open note"] = function()
  child.lua [[
    write_config(vault_a, "templates.json", { folder = "First" })
    vim.fn.writefile({ "# Note" }, vim.fs.joinpath(vault_a, "note.md"))
    configure()
    vim.cmd("edit " .. vim.fn.fnameescape(vim.fs.joinpath(vault_a, "note.md")))
  ]]
  h.child_wait_for_lsp_client(child, "obsidian-ls")
  child.lua [[
    write_config(vault_a, "templates.json", { folder = "Second", timeFormat = "HH" })
    configure()
  ]]
  eq("Second", child.lua_get "Obsidian.opts.templates.folder")
  eq("HH", child.lua_get "Obsidian.opts.templates.time_format")
  eq(true, child.lua_get "vim.b.obsidian_buffer")
end

T["UTF-8 BOM does not change empty core plugin defaults"] = function()
  child.lua [[
    local dir = vim.fs.joinpath(vault_a, ".obsidian")
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({ string.char(239, 187, 191) .. "{}" }, vim.fs.joinpath(dir, "core-plugins.json"))
    configure()
  ]]
  eq(
    { true, true, false },
    child.lua_get "{ Obsidian.opts.templates.enabled, Obsidian.opts.daily_notes.enabled, Obsidian.opts.unique_note.enabled }"
  )
end

T["unreadable files warn and retain Lua settings"] = function()
  child.lua [[
    write_config(vault_a, "templates.json", { folder = "App" })
    _G.warnings = {}
    require("obsidian.log").warn_once = function(...) table.insert(warnings, { ... }) end
    local open = io.open
    io.open = function(path, mode)
      if vim.endswith(path, "/templates.json") and mode == "r" then return nil, "permission denied" end
      return open(path, mode)
    end
    configure()
    io.open = open
  ]]
  eq("lua-templates", child.lua_get "Obsidian.opts.templates.folder")
  eq(1, child.lua_get "#warnings")
end

T["explicit root folders do not inherit the app new-note folder"] = function()
  child.lua [[
    write_config(vault_a, "app.json", { newFileLocation = "folder", newFileFolderPath = "Inbox" })
    write_config(vault_a, "daily-notes.json", { folder = "/" })
    write_config(vault_a, "zk-prefixer.json", { folder = "/" })
    configure()
  ]]
  eq("", child.lua_get "Obsidian.opts.daily_notes.folder")
  eq("", child.lua_get "Obsidian.opts.unique_note.folder")
end

T["note-relative attachments without a source file fall back to the vault"] = function()
  child.lua [[
    write_config(vault_a, "app.json", { attachmentFolderPath = "./images" })
    configure()
    _G.destination = require("obsidian.attachment").destination_path("photo.png", "")
  ]]
  eq(true, child.lua_get 'destination == vim.fs.joinpath(vault_a, "images/photo.png")')
end

return T
