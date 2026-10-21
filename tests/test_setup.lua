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
        for _, dir in ipairs { vault_a, vault_b } do
          vim.fn.mkdir(vim.fs.joinpath(dir, ".obsidian"), "p")
          vim.fn.writefile({ "# Note" }, vim.fs.joinpath(dir, "note.md"))
        end
        _G.configure = function(path, extra)
          local opts = vim.tbl_deep_extend("force", {
            legacy_commands = false,
            workspaces = { { path = path } },
            ui = { enable = false },
            footer = { enabled = false },
            frontmatter = { enabled = false },
            log_level = vim.log.levels.ERROR,
          }, extra or {})
          return require("obsidian").setup(opts)
        end
        _G.open_note = function(path)
          vim.cmd("edit " .. vim.fn.fnameescape(vim.fs.joinpath(path, "note.md")))
          return vim.api.nvim_get_current_buf()
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

T["repeated setup updates the current note without duplicating callbacks"] = function()
  child.lua [[
    _G.writes = 0
    configure(vault_a)
    open_note(vault_a)
    for i = 1, 3 do
      configure(vault_a, {
        notes_subdir = "updated",
        callbacks = { pre_write_note = function() writes = writes + 1 end },
      })
    end
    vim.cmd "write"
  ]]
  eq("updated", child.lua_get "Obsidian.opts.notes_subdir")
  eq(1, child.lua_get "writes")
  eq(1, child.lua_get '#vim.api.nvim_get_autocmds { group = "obsidian_setup", event = "BufWritePre", buffer = 0 }')
  eq(true, child.lua_get "vim.b.obsidian_buffer")
end

T["repeated setup preserves completion refresh handlers without duplicates"] = function()
  child.lua [[
    configure(vault_a)
    open_note(vault_a)
    _G.observed, _G.refreshed = 0, 0
    require("obsidian.inlay_hints.completion").observe = function()
      observed = observed + 1
      return false, true
    end
    require("obsidian.inlay_hints").schedule_refresh = function()
      refreshed = refreshed + 1
    end
    configure(vault_a)
    configure(vault_a)
    for _, event in ipairs { "TextChanged", "InsertLeave", "CursorMovedI" } do
      vim.api.nvim_exec_autocmds(event, { buffer = 0 })
    end
  ]]
  eq(2, child.lua_get "observed")
  eq(3, child.lua_get "refreshed")
  child.lua [[
    configure(vault_b)
    for _, event in ipairs { "TextChanged", "InsertLeave", "CursorMovedI" } do
      vim.api.nvim_exec_autocmds(event, { buffer = 0 })
    end
  ]]
  eq(2, child.lua_get "observed")
  eq(3, child.lua_get "refreshed")
end

T["setup recovers from an incomplete previous state"] = function()
  child.lua [[
    _G.Obsidian = { opts = {} }
    open_note(vault_a)
    configure(vault_a)
  ]]
  eq(true, child.lua_get "tostring(Obsidian.dir) == vault_a")
  eq(true, child.lua_get "vim.b.obsidian_buffer")
end

T["setup attaches an already open note"] = function()
  child.lua [[
    open_note(vault_a)
    configure(vault_a)
  ]]
  eq(true, child.lua_get "vim.b.obsidian_buffer")
  h.child_wait_for_lsp_client(child, "obsidian-ls")
end

T["removed workspaces stop managing their open buffers"] = function()
  child.lua [[
    configure(vault_a)
    _G.old_buf = open_note(vault_a)
  ]]
  h.child_wait_for_lsp_client(child, "obsidian-ls")
  child.lua [[
    _G.writes = 0
    configure(vault_b, {
      frontmatter = { enabled = true, func = function() return { changed = true } end },
      callbacks = { pre_write_note = function() writes = writes + 1 end },
    })
    vim.cmd "write"
  ]]
  eq(vim.NIL, child.lua_get "vim.b[old_buf].obsidian_buffer")
  eq(0, child.lua_get '#vim.lsp.get_clients { bufnr = old_buf, name = "obsidian-ls" }')
  eq(0, child.lua_get "writes")
  eq({ "# Note" }, child.lua_get 'vim.fn.readfile(vim.fs.joinpath(vault_a, "note.md"))')
  child.lua "open_note(vault_b)"
  eq(true, child.lua_get "vim.b.obsidian_buffer")
  h.child_wait(
    child,
    [[
    local clients = vim.lsp.get_clients { bufnr = 0, name = "obsidian-ls" }
    return #clients == 1 and clients[1].config.root_dir == vault_b
  ]],
    { desc = "new vault LSP attachment" }
  )
end

T["workspace overrides and cache stay isolated after reconfiguration"] = function()
  child.lua [[
    configure(vault_a)
    open_note(vault_a)
    configure(vault_a, {
      cache = { enabled = true, backend = "memory" },
      workspaces = {
        { name = "A", path = vault_a, overrides = { notes_subdir = "notes-a" } },
        { name = "B", path = vault_b, overrides = { notes_subdir = "notes-b" } },
      },
    })
  ]]
  h.child_wait(child, 'return require("obsidian.cache").is_ready()', { desc = "vault A cache" })
  eq("notes-a", child.lua_get "Obsidian.opts.notes_subdir")
  eq(true, child.lua_get 'require("obsidian.cache").notes.all()[vim.fs.joinpath(vault_a, "note.md")] ~= nil')
  child.lua "open_note(vault_b)"
  h.child_wait(child, 'return require("obsidian.cache").is_ready()', { desc = "vault B cache" })
  eq("notes-b", child.lua_get "Obsidian.opts.notes_subdir")
  eq(false, child.lua_get 'require("obsidian.cache").notes.all()[vim.fs.joinpath(vault_a, "note.md")] ~= nil')
  eq(true, child.lua_get 'require("obsidian.cache").notes.all()[vim.fs.joinpath(vault_b, "note.md")] ~= nil')
  child.lua "open_note(vault_a)"
  eq("notes-a", child.lua_get "Obsidian.opts.notes_subdir")
end

T["reconfiguration rebuilds volatile vault indexes with the new options"] = function()
  child.lua [[
    configure(vault_a, { notes_subdir = "first" })
    _G.index = require("obsidian.cache.volatile").vault_index {
      build = function(_, done) done(Obsidian.opts.notes_subdir) end,
    }
    index:get(vault_a, {}, function(value) _G.before = value end)
    configure(vault_a, { notes_subdir = "second" })
    index:get(vault_a, {}, function(value) _G.after = value end)
    index:dispose()
  ]]
  eq("first", child.lua_get "before")
  eq("second", child.lua_get "after")
end

T["reconfiguration removes disabled footer and UI handlers"] = function()
  child.lua [[
    _G.ui_callbacks = {}
    require("obsidian.async").throttle = function(callback)
      table.insert(ui_callbacks, callback)
      return function() end
    end
    configure(vault_a, { ui = { enable = true, ignore_conceal_warn = true }, footer = { enabled = true } })
    _G.note_buf = open_note(vault_a)
    vim.api.nvim_buf_set_lines(note_buf, 0, -1, false, { "- [ ] Task" })
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = note_buf })
    configure(vault_a, { ui = { enable = false }, footer = { enabled = false } })
  ]]
  child.lua "for _, callback in ipairs(ui_callbacks) do callback { buf = note_buf } end"
  eq(
    0,
    child.lua_get [[#vim.tbl_filter(function(event)
    return event.group_name == "ObsidianUIa" or event.group_name == "obsidian.footer-" .. note_buf
  end, vim.api.nvim_get_autocmds {})]]
  )
  eq(
    0,
    child.lua_get '#vim.api.nvim_buf_get_extmarks(note_buf, vim.api.nvim_create_namespace("obsidian.footer"), 0, -1, {})'
  )
  eq(
    0,
    child.lua_get '#vim.api.nvim_buf_get_extmarks(note_buf, vim.api.nvim_create_namespace("ObsidianUI"), 0, -1, {})'
  )
end

T["reconfiguration restores buffer options and preserves user mappings"] = function()
  child.lua [[
    open_note(vault_a)
    vim.bo.includeexpr = "original"
    configure(vault_a)
    vim.keymap.set("n", "<CR>", "user", { buffer = true, desc = "User mapping" })
    configure(vault_b)
  ]]
  eq("original", child.lua_get "vim.bo.includeexpr")
  eq("user", child.lua_get 'vim.fn.maparg("<CR>", "n")')
  eq("", child.lua_get 'vim.fn.maparg("]o", "n")')
end

T["reconfiguration pauses the previous continuous sync backend"] = function()
  child.lua [[
    _G.started, _G.paused = {}, {}
    require("obsidian.sync").register("test", {
      is_configured = function() return true end,
      start = function(dir) table.insert(started, dir) end,
      pause = function(dir) table.insert(paused, dir) end,
    })
    configure(vault_a, { sync = { enabled = true, backend = "test", trigger = "continuous" } })
    configure(vault_b)
  ]]
  eq(true, child.lua_get "#started == 1 and started[1] == vault_a")
  eq(true, child.lua_get "#paused == 1 and paused[1] == vault_a")
end

T["reconfiguration cancels pending write sync"] = function()
  child.lua [[
    _G.sync_calls = 0
    require("obsidian.sync").register("test", {
      is_configured = function() return true end,
      sync_once = function() sync_calls = sync_calls + 1 end,
    })
    configure(vault_a, { sync = { enabled = true, backend = "test", trigger = "on_write" } })
    local new_timer = vim.uv.new_timer
    _G.timer_closed = false
    vim.uv.new_timer = function()
      return {
        start = function(_, _, _, callback) _G.pending_sync = callback end,
        stop = function() end,
        close = function() timer_closed = true end,
      }
    end
    require("obsidian.sync").sync_once_debounced()
    vim.uv.new_timer = new_timer
    configure(vault_b)
  ]]
  eq(true, child.lua_get "timer_closed")
  h.child_await(
    child,
    [[
    pending_sync()
    vim.schedule(function() done(true) end)
  ]],
    { desc = "cancelled sync callback" }
  )
  eq(0, child.lua_get "sync_calls")
end

T["invalid reconfiguration preserves the working configuration"] = function()
  child.lua [[
    configure(vault_a)
    open_note(vault_a)
    _G.previous_state = Obsidian
    vim.notify = function() end
    configure(vault_b, { new_notes_location = "invalid" })
  ]]
  eq(true, child.lua_get "Obsidian == previous_state")
  eq(true, child.lua_get "tostring(Obsidian.dir) == vault_a")
  eq(true, child.lua_get "vim.b.obsidian_buffer")
end

T["local Lua configuration resolves its vault independently of cwd"] = function()
  child.lua [[
    local config_path = vim.fs.joinpath(vault_a, ".nvim.lua")
    vim.fn.writefile({
      'local source = debug.getinfo(1, "S").source:gsub("^@", "")',
      'local root = vim.fs.dirname(vim.fs.normalize(source))',
      'configure(root, { notes_subdir = "notes", new_notes_location = "notes_subdir", note_id_func = function(title) return title end })',
    }, config_path)
    vim.cmd("cd " .. vim.fn.fnameescape(vault_b))
    vim.cmd("source " .. vim.fn.fnameescape(config_path))
    open_note(vault_a)
    _G.created_note = require("obsidian.note").create { id = "local-note" }
    vim.cmd("cd " .. vim.fn.fnameescape(vault_a))
    vim.cmd("source " .. vim.fn.fnameescape(config_path))
  ]]
  eq(true, child.lua_get "tostring(Obsidian.dir) == vault_a")
  eq(true, child.lua_get 'tostring(created_note.path) == vim.fs.joinpath(vault_a, "notes", "local-note.md")')
end

T["exrc applies vault setup at startup before opening a nested note"] = function()
  local repo = vim.uv.cwd()
  local vault = vim.fs.joinpath(root, "a")
  local config_path = vim.fs.joinpath(vault, ".nvim.lua")
  local config_home = vim.fs.joinpath(root, "config")
  local init_path = vim.fs.joinpath(config_home, "nvim", "init.lua")
  vim.fn.mkdir(vim.fs.dirname(init_path), "p")
  local state_path = vim.fs.joinpath(root, "state")
  local note_path = vim.fs.joinpath(vault, "nested", "note.md")
  vim.fn.mkdir(vim.fs.dirname(note_path), "p")
  vim.fn.writefile({ "# Nested note" }, note_path)
  vim.fn.writefile({
    'local source = debug.getinfo(1, "S").source:gsub("^@", "")',
    "local root = vim.fs.dirname(vim.fs.normalize(source))",
    'require("obsidian").setup {',
    "  legacy_commands = false, workspaces = { { path = root } },",
    '  notes_subdir = "local-notes", ui = { enable = false }, footer = { enabled = false },',
    "}",
  }, config_path)
  vim.fn.writefile({
    string.format("vim.opt.rtp:append(%q)", repo),
    "vim.opt.exrc = true",
    'vim.fn.mkdir(vim.fn.stdpath("state"), "p")',
    string.format("local config_buf = vim.fn.bufadd(%q)", config_path),
    "vim.fn.bufload(config_buf)",
    'assert(vim.secure.trust { action = "allow", bufnr = config_buf })',
    string.format(
      'require("obsidian").setup { legacy_commands = false, workspaces = { { path = %q } } }',
      vim.fs.joinpath(root, "b")
    ),
    'vim.cmd "filetype on"',
  }, init_path)
  local report_path = vim.fs.joinpath(root, "report.json")
  local report = string.format(
    [[lua vim.fn.writefile({ vim.json.encode {
    dir = tostring(Obsidian.dir), notes_subdir = Obsidian.opts.notes_subdir,
    is_note = vim.b.obsidian_buffer, file = vim.api.nvim_buf_get_name(0),
  } }, %q)]],
    report_path
  )
  local result = vim
    .system({ vim.v.progpath, "--headless", "--noplugin", "-i", "NONE", note_path, "-c", report, "-c", "qa!" }, {
      cwd = vault,
      env = {
        XDG_CONFIG_HOME = config_home,
        XDG_CONFIG_DIRS = config_home,
        XDG_STATE_HOME = state_path,
        XDG_DATA_HOME = vim.fs.joinpath(root, "data"),
        XDG_CACHE_HOME = vim.fs.joinpath(root, "cache"),
        NVIM_APPNAME = "nvim",
        VIMINIT = "",
        EXINIT = "",
      },
      text = true,
    })
    :wait(5000)
  eq({ 0, "" }, { result.code, result.stderr })
  local actual = vim.json.decode(table.concat(vim.fn.readfile(report_path), "\n"))
  eq("local-notes", actual.notes_subdir)
  eq(vault, actual.dir)
  eq(true, actual.is_note)
  eq(note_path, vim.fs.normalize(actual.file))
end

return T
