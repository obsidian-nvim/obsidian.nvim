local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local Path = require "obsidian.path"
local helpers = require "tests.helpers"

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

T["cache backends"] = new_set()
T["json backend"] = new_set()

T["json backend"]["persists schema v2 entries"] = function()
  local dir = Path.temp { suffix = "-obsidian-cache-json" }
  dir:mkdir { parents = true }
  Obsidian = { dir = dir }
  local path = tostring(dir / "index.json")
  local vault = vim.fs.normalize(tostring(dir / "vault"))
  local backend_module = require "obsidian.cache.json_backend"
  local backend = backend_module.open { path = path, vault = vault }
  local note_path = vim.fs.joinpath(vault, "Note.md")
  backend:put(note_path, {
    kind = "note",
    stat = { mtime_sec = 1, mtime_nsec = 2, size = 3 },
  })
  backend:flush()

  local decoded = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
  eq(2, decoded.schema_version)
  eq(1, decoded.indexer_version)
  eq(vault, decoded.vault)
  eq("note", decoded.entries[note_path].kind)
  eq(nil, decoded.notes)

  local reopened = backend_module.open { path = path, vault = vault }
  eq("note", reopened:get(note_path).kind)
end

T["json backend"]["rebuilds incompatible cache envelopes"] = function()
  local dir = Path.temp { suffix = "-obsidian-cache-json" }
  dir:mkdir { parents = true }
  Obsidian = { dir = dir }
  local path = tostring(dir / "index.json")
  local vault = vim.fs.normalize(tostring(dir / "vault"))
  vim.fn.writefile({
    vim.json.encode {
      version = 1,
      vault = vault,
      notes = {
        [vim.fs.joinpath(vault, "Stale.md")] = { tags = { "stale" } },
      },
    },
  }, path)

  local backend = require("obsidian.cache.json_backend").open { path = path, vault = vault }
  eq({}, backend:all())
  backend:flush()

  local decoded = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
  eq(2, decoded.schema_version)
  eq(1, decoded.indexer_version)
  eq(nil, decoded.version)
  eq(nil, decoded.notes)
end

T["cache backends"]["uses a registered backend by name"] = function()
  local dir = Path.temp { suffix = "-obsidian-cache" }
  dir:mkdir { parents = true }
  helpers.write("# Note", dir / "Note.md")
  Obsidian = { dir = dir }

  local opened = false
  local store = { data = {} }
  function store:get(key)
    return self.data[key]
  end
  function store:all()
    return self.data
  end
  function store:put(key, row)
    self.data[key] = row
  end
  function store:delete(key)
    self.data[key] = nil
  end
  function store:flush() end
  function store:close() end

  local cache = require "obsidian.cache"
  cache.register("custom-test", {
    open = function(opts)
      local vault = vim.fs.normalize(tostring(dir))
      local expected_root = vim.fs.joinpath(vim.fn.stdpath "cache", "obsidian.nvim", vim.fn.sha256(vault):sub(1, 16))
      local expected_path = vim.fs.joinpath(expected_root, "index.json")
      opened = opts.vault == vault and opts.root == expected_root and opts.path == expected_path
      return store
    end,
  })

  cache.setup { enabled = true, backend = "custom-test" }
  vim.wait(1000, function()
    return cache.is_ready()
  end)

  eq(true, opened)
  eq(1, cache.notes.count())
end

T["cache backends"]["uses file ignore filters"] = function()
  local dir = Path.temp { suffix = "-obsidian-cache" }
  dir:mkdir { parents = true }
  Path.new(dir / "skip"):mkdir()
  helpers.write("# Keep", dir / "Keep.md")
  helpers.write("# Skip", dir / "skip" / "Skip.md")
  Obsidian = {
    dir = dir,
    opts = { file = { ignore_filters = { "skip/" } } },
  }
  require("obsidian.ignore").clear_cache()

  local cache = require "obsidian.cache"
  cache.setup { enabled = true, backend = "memory" }
  vim.wait(1000, function()
    return cache.is_ready()
  end)

  eq(true, cache.notes.find(tostring(dir / "Keep.md")) ~= nil)
  eq(nil, cache.notes.find(tostring(dir / "skip" / "Skip.md")))
end

T["cache backends"]["stores typed compact note rows"] = function()
  local dir = Path.temp { suffix = "-obsidian-cache" }
  dir:mkdir { parents = true }
  local note_path = tostring(dir / "Note.md")
  helpers.write("---\ntags: [Foo]\n---\n# Note\n#Inline", note_path)
  Obsidian = { dir = dir }

  local cache = require "obsidian.cache"
  cache.setup { enabled = true, backend = "memory" }
  vim.wait(1000, function()
    return cache.is_ready()
  end)

  local row = cache.notes.find(note_path)
  eq({ "foo", "inline" }, row.tags)
  eq("note", row.kind)
  eq("number", type(row.stat.mtime_nsec))
  eq("number", type(row.stat.mtime_sec))
  eq("number", type(row.stat.size))
  eq(nil, row.path)
  eq(nil, row.rel_path)
  eq(nil, row.basename)
  eq(nil, row.ext)
  eq(nil, row.folder)
  eq(nil, row.has_frontmatter)
  eq(nil, row.frontmatter_end_line)
  eq(nil, row.aliases)
  eq(nil, row.links_out)
  eq(nil, row.tasks)
end

T["cache backends"]["detects same-size edits within one second"] = function()
  local dir = Path.temp { suffix = "-obsidian-cache" }
  dir:mkdir { parents = true }
  local note_path = tostring(dir / "Note.md")
  helpers.write("#one", note_path)
  Obsidian = { dir = dir }

  local store = { data = {} }
  function store:get(key)
    return self.data[key]
  end
  function store:all()
    return self.data
  end
  function store:put(key, row)
    self.data[key] = row
  end
  function store:delete(key)
    self.data[key] = nil
  end
  function store:flush() end
  function store:close() end

  local cache = require "obsidian.cache"
  cache.register("freshness-test", {
    open = function()
      return store
    end,
  })

  cache.setup { enabled = true, backend = "freshness-test" }
  vim.wait(1000, function()
    return cache.is_ready()
  end)
  eq({ "one" }, cache.notes.find(note_path).tags)

  local old_stat = assert(vim.uv.fs_stat(note_path))
  helpers.write("#two", note_path)
  local target_nsec = old_stat.mtime.nsec < 500000000 and 750000000 or 250000000
  assert(vim.uv.fs_utime(note_path, old_stat.atime.sec, old_stat.mtime.sec + target_nsec / 1000000000))
  local new_stat = assert(vim.uv.fs_stat(note_path))
  eq(old_stat.mtime.sec, new_stat.mtime.sec)
  eq(true, old_stat.mtime.nsec ~= new_stat.mtime.nsec)
  eq(old_stat.size, new_stat.size)

  cache.setup { enabled = true, backend = "freshness-test" }
  vim.wait(1000, function()
    return cache.is_ready()
  end)
  eq({ "two" }, cache.notes.find(note_path).tags)
end

T["cache backends"]["hides persisted rows until startup validation finishes"] = function()
  local dir = Path.temp { suffix = "-obsidian-cache" }
  dir:mkdir { parents = true }
  local note_path = tostring(dir / "Note.md")
  helpers.write("#fresh", note_path)
  Obsidian = { dir = dir }

  local stat = assert(vim.uv.fs_stat(note_path))
  local store = {
    data = {
      [vim.fs.normalize(note_path)] = {
        kind = "attachment",
        extension = "md",
        stat = {
          mtime_sec = stat.mtime.sec,
          mtime_nsec = stat.mtime.nsec,
          size = stat.size,
        },
      },
    },
  }
  function store:get(key)
    return self.data[key]
  end
  function store:all()
    return self.data
  end
  function store:put(key, row)
    self.data[key] = row
  end
  function store:delete(key)
    self.data[key] = nil
  end
  function store:flush() end
  function store:close() end

  local cache = require "obsidian.cache"
  cache.register("validation-test", {
    open = function()
      return store
    end,
  })

  cache.setup { enabled = true, backend = "validation-test" }
  eq(nil, cache.notes.find(note_path))
  eq(0, cache.notes.count())

  vim.wait(1000, function()
    return cache.is_ready()
  end)
  eq({ "fresh" }, cache.notes.find(note_path).tags)
end

T["cache backends"]["refreshes directly on LSP didSave"] = function()
  local dir = Path.temp { suffix = "-obsidian-cache" }
  dir:mkdir { parents = true }
  local note_path = tostring(dir / "Note.md")
  helpers.write("#one", note_path)
  Obsidian = { dir = dir }

  local cache = require "obsidian.cache"
  cache.setup { enabled = true, backend = "memory" }
  vim.wait(1000, function()
    return cache.is_ready()
  end)
  eq({ "one" }, cache.notes.find(note_path).tags)

  helpers.write("#two", note_path)
  require "obsidian.lsp.handlers.did_save" {
    textDocument = { uri = vim.uri_from_fname(note_path) },
  }

  eq({ "two" }, cache.notes.find(note_path).tags)
end

T["cache backends"]["removes stale data when parsing fails"] = function()
  local dir = Path.temp { suffix = "-obsidian-cache" }
  dir:mkdir { parents = true }
  local note_path = tostring(dir / "Note.md")
  helpers.write("#one", note_path)
  Obsidian = { dir = dir }

  local cache = require "obsidian.cache"
  cache.setup { enabled = true, backend = "memory" }
  vim.wait(1000, function()
    return cache.is_ready()
  end)
  eq({ "one" }, cache.notes.find(note_path).tags)

  local Note = require "obsidian.note"
  local from_lines = Note.from_lines
  Note.from_lines = function()
    error "parse failed"
  end
  require("obsidian.lsp.watchfiles").handle {
    { type = "changed", path = note_path },
  }
  Note.from_lines = from_lines

  eq(nil, cache.notes.find(note_path))
end

T["cache backends"]["indexes markdown-like extensions"] = function()
  local dir = Path.temp { suffix = "-obsidian-cache" }
  dir:mkdir { parents = true }
  helpers.write("# Note", dir / "Note.md")
  helpers.write("# Page", dir / "Page.markdown")
  helpers.write("# Query", dir / "Query.qmd")
  helpers.write("# Base", dir / "Base.base")
  Obsidian = { dir = dir }

  local cache = require "obsidian.cache"
  cache.setup { enabled = true, backend = "memory" }
  vim.wait(1000, function()
    return cache.is_ready()
  end)

  eq(4, cache.notes.count())
  eq(true, cache.notes.find(tostring(dir / "Page.markdown")) ~= nil)
  eq(true, cache.notes.find(tostring(dir / "Query.qmd")) ~= nil)
  eq(true, cache.notes.find(tostring(dir / "Base.base")) ~= nil)
end

T["cache backends"]["indexes typed attachment rows separately from notes"] = function()
  local dir = Path.temp { suffix = "-obsidian-cache" }
  dir:mkdir { parents = true }
  Obsidian = { dir = dir }

  local paths = {}
  for _, ext in ipairs(require("obsidian.filetypes").attachment_extensions) do
    local path = dir / ("File." .. ext)
    helpers.write("attachment", path)
    paths[#paths + 1] = tostring(path)
  end
  local note_path = tostring(dir / "Note.md")
  helpers.write("# Note", note_path)

  local cache = require "obsidian.cache"
  cache.setup { enabled = true, backend = "memory" }
  vim.wait(1000, function()
    return cache.is_ready()
  end)

  eq(1, cache.notes.count())
  eq(#paths, cache.attachments.count())
  eq(true, cache.notes.find(note_path) ~= nil)
  eq(nil, cache.attachments.find(note_path))
  for _, path in ipairs(paths) do
    local row = cache.attachments.find(path)
    eq("attachment", row.kind)
    eq(require("obsidian.filetypes").extension(path), row.extension)
    eq("number", type(row.stat.mtime_nsec))
    eq(nil, cache.notes.find(path))
  end
  cache.notes.delete(paths[1])
  eq(true, cache.attachments.find(paths[1]) ~= nil)
end

T["cache backends"]["file watcher registers attachments only when cache is enabled"] = function()
  Obsidian = { opts = { cache = { enabled = false } } }
  local captured
  require "obsidian.lsp.handlers.initialized"(nil, {
    server_request = function(_, registration)
      captured = registration
    end,
  })

  local watched = {}
  for _, watcher in ipairs(captured.registrations[1].registerOptions.watchers) do
    local ext = watcher.globPattern:match "%.([^%.]+)$"
    watched[ext] = true
  end

  eq(true, watched.md)
  eq(nil, watched.png)

  Obsidian.opts.cache.enabled = true
  require "obsidian.lsp.handlers.initialized"(nil, {
    server_request = function(_, registration)
      captured = registration
    end,
  })

  watched = {}
  for _, watcher in ipairs(captured.registrations[1].registerOptions.watchers) do
    local ext = watcher.globPattern:match "%.([^%.]+)$"
    watched[ext] = true
  end
  for _, ext in ipairs(require("obsidian.filetypes").attachment_extensions) do
    eq(true, watched[ext])
  end
end

T["cache backends"]["excludes vault internals"] = function()
  local dir = Path.temp { suffix = "-obsidian-cache" }
  dir:mkdir { parents = true }
  Path.new(dir / ".obsidian" / "plugins" / "example"):mkdir { parents = true }
  Path.new(dir / ".git"):mkdir()
  helpers.write("# Note", dir / "Note.md")
  helpers.write("image", dir / "Photo.png")
  helpers.write("# Internal", dir / ".obsidian" / "plugins" / "example" / "README.md")
  helpers.write("internal", dir / ".git" / "logo.png")
  Obsidian = { dir = dir }

  local cache = require "obsidian.cache"
  cache.setup { enabled = true, backend = "memory" }
  vim.wait(1000, function()
    return cache.is_ready()
  end)

  eq(1, cache.notes.count())
  eq(1, cache.attachments.count())
  eq(nil, cache.notes.find(tostring(dir / ".obsidian" / "plugins" / "example" / "README.md")))
  eq(nil, cache.attachments.find(tostring(dir / ".git" / "logo.png")))
end

T["cache backends"]["updates typed attachments from watched-file events"] = function()
  local dir = Path.temp { suffix = "-obsidian-cache" }
  dir:mkdir { parents = true }
  Obsidian = { dir = dir }

  local cache = require "obsidian.cache"
  cache.setup { enabled = true, backend = "memory" }
  vim.wait(1000, function()
    return cache.is_ready()
  end)

  local old_path = tostring(dir / "Old.PNG")
  local new_path = tostring(dir / "New.pdf")
  helpers.write("old", old_path)
  require("obsidian.lsp.watchfiles").handle {
    { type = "created", path = old_path },
  }
  eq("png", cache.attachments.get(old_path).extension)
  eq(nil, cache.notes.find(old_path))

  helpers.write("new attachment", new_path)
  vim.fn.delete(old_path)
  require("obsidian.lsp.watchfiles").handle {
    { type = "renamed", old_path = old_path, new_path = new_path },
  }
  eq(nil, cache.attachments.find(old_path))
  eq("pdf", cache.attachments.get(new_path).extension)

  vim.fn.delete(new_path)
  require("obsidian.lsp.watchfiles").handle {
    { type = "deleted", path = new_path },
  }
  eq(nil, cache.attachments.find(new_path))
end

T["cache backends"]["handles raw LSP watched-file events"] = function()
  local dir = Path.temp { suffix = "-obsidian-cache" }
  dir:mkdir { parents = true }
  Obsidian = { dir = dir }

  local cache = require "obsidian.cache"
  cache.setup { enabled = true, backend = "memory" }
  vim.wait(1000, function()
    return cache.is_ready()
  end)

  local note_path = tostring(dir / "Fresh.md")
  helpers.write("# Fresh", note_path)
  require "obsidian.lsp.handlers.did_change_watched_files" {
    changes = {
      {
        uri = vim.uri_from_fname(note_path),
        type = vim.lsp.protocol.FileChangeType.Created,
      },
    },
  }

  eq(true, cache.notes.find(note_path) ~= nil)
end

T["cache backends"]["rename lifecycle uses store operations only"] = function()
  local dir = Path.temp { suffix = "-obsidian-cache" }
  dir:mkdir { parents = true }
  local old_path = dir / "Old.md"
  local new_path = dir / "New.md"
  helpers.write("# Old", old_path)
  Obsidian = { dir = dir }

  local store = { data = {} }
  function store:get(key)
    return self.data[key]
  end
  function store:all()
    return self.data
  end
  function store:put(key, row)
    self.data[key] = row
  end
  function store:delete(key)
    self.data[key] = nil
  end
  function store:flush() end
  function store:close() end

  local cache = require "obsidian.cache"
  cache.register("rename-test", {
    open = function()
      return store
    end,
  })

  cache.setup { enabled = true, backend = "rename-test" }
  vim.wait(1000, function()
    return cache.is_ready()
  end)

  helpers.write("# New", new_path)
  vim.fn.delete(tostring(old_path))
  require("obsidian.lsp.watchfiles").handle {
    { type = "renamed", old_path = tostring(old_path), new_path = tostring(new_path) },
  }

  eq(nil, cache.notes.find(tostring(old_path)))
  eq(true, cache.notes.find(tostring(new_path)) ~= nil)
end

T["cache backends"]["rename into ignored path removes old entry only"] = function()
  local dir = Path.temp { suffix = "-obsidian-cache" }
  dir:mkdir { parents = true }
  Path.new(dir / "skip"):mkdir()
  local old_path = dir / "Old.md"
  local new_path = dir / "skip" / "New.md"
  helpers.write("# Old", old_path)
  Obsidian = {
    dir = dir,
    opts = { file = { ignore_filters = { "skip/" } } },
  }
  require("obsidian.ignore").clear_cache()

  local cache = require "obsidian.cache"
  cache.setup { enabled = true, backend = "memory" }
  vim.wait(1000, function()
    return cache.is_ready()
  end)

  helpers.write("# New", new_path)
  vim.fn.delete(tostring(old_path))
  require("obsidian.lsp.watchfiles").handle {
    { type = "renamed", old_path = tostring(old_path), new_path = tostring(new_path) },
  }

  eq(nil, cache.notes.find(tostring(old_path)))
  eq(nil, cache.notes.find(tostring(new_path)))
end

T["cache backends"]["setup is idempotent and disabled tears down"] = function()
  local dir = Path.temp { suffix = "-obsidian-cache" }
  dir:mkdir { parents = true }
  Obsidian = { dir = dir }

  local puts = 0
  local store = { data = {} }
  function store:get(key)
    return self.data[key]
  end
  function store:all()
    return self.data
  end
  function store:put(key, row)
    puts = puts + 1
    self.data[key] = row
  end
  function store:delete(key)
    self.data[key] = nil
  end
  function store:flush() end
  function store:close() end

  local cache = require "obsidian.cache"
  cache.register("idempotent-test", {
    open = function()
      return store
    end,
  })

  cache.setup { enabled = true, backend = "idempotent-test" }
  cache.setup { enabled = true, backend = "idempotent-test" }
  vim.wait(1000, function()
    return cache.is_ready()
  end)

  local note_path = tostring(dir / "Fresh.md")
  helpers.write("# Fresh", note_path)
  require("obsidian.lsp.watchfiles").handle {
    { type = "created", path = note_path },
  }

  eq(1, puts)

  cache.setup { enabled = false }
  eq(false, cache.is_enabled())
end

return T
