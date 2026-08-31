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
      local expected_path =
        vim.fs.joinpath(vim.fn.stdpath "cache", "obsidian.nvim", vim.fn.sha256(vault):sub(1, 16) .. ".json")
      opened = opts.vault == vault and opts.path == expected_path
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

T["cache backends"]["round trips query metadata through JSON"] = function()
  local dir = Path.temp { suffix = "-obsidian-cache-json" }
  dir:mkdir { parents = true }
  local cache_path = tostring(dir / "cache.json")
  local backend = require "obsidian.cache.json_backend"
  local store = backend.open { path = cache_path, vault = tostring(dir) }
  store:put("/vault/Note.md", {
    frontmatter = {
      present = true,
      values = {
        empty_list = {},
        empty_string = "",
        explicit_null = vim.NIL,
        flag = false,
        number = 3,
      },
    },
    tag_locations = { { text = "#Work", normalized = "#work", line = 4, col = 2 } },
    tasks = { { line = 5, col = 7, state = " ", text = "todo", raw = "- [ ] todo" } },
  })
  store:flush()

  local reopened = backend.open { path = cache_path, vault = tostring(dir) }
  local row = reopened:get "/vault/Note.md"
  eq(vim.NIL, row.frontmatter.values.explicit_null)
  eq("", row.frontmatter.values.empty_string)
  eq({}, row.frontmatter.values.empty_list)
  eq(false, row.frontmatter.values.flag)
  eq(3, row.frontmatter.values.number)
  eq("#Work", row.tag_locations[1].text)
  eq("- [ ] todo", row.tasks[1].raw)
  vim.fn.delete(tostring(dir), "rf")
end

T["cache backends"]["discards caches from an older schema"] = function()
  local dir = Path.temp { suffix = "-obsidian-cache-json" }
  dir:mkdir { parents = true }
  local cache_path = tostring(dir / "cache.json")
  helpers.write(
    vim.json.encode {
      version = 2,
      vault = tostring(dir),
      notes = { ["/vault/Stale.md"] = { mtime = 1, size = 1 } },
    },
    cache_path
  )

  local backend = require "obsidian.cache.json_backend"
  local store = backend.open { path = cache_path, vault = tostring(dir) }
  eq(nil, store:get "/vault/Stale.md")
  vim.fn.delete(tostring(dir), "rf")
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

T["cache backends"]["stores searchable rows"] = function()
  local dir = Path.temp { suffix = "-obsidian-cache" }
  dir:mkdir { parents = true }
  local note_path = tostring(dir / "Note.md")
  helpers.write("---\nid: custom-note\ntags: [Foo]\n---\n# Note\n#Inline", note_path)
  Obsidian = { dir = dir }

  local cache = require "obsidian.cache"
  cache.setup { enabled = true, backend = "memory" }
  vim.wait(1000, function()
    return cache.is_ready()
  end)

  local row = cache.notes.find(note_path)
  eq({ "foo", "inline" }, row.tags)
  eq("number", type(row.mtime_nsec))
  eq(nil, row.path)
  eq("Note.md", row.relative_path)
  eq("Note.md", row.filename)
  eq("Note", row.basename)
  eq("md", row.extension)
  eq("markdown", row.kind)
  eq(5, row.line_count)
  eq(true, row.frontmatter.present)
  eq({ "Foo" }, row.frontmatter.values.tags)
  eq("#Inline", row.tag_locations[2].text)
  eq(5, row.tag_locations[2].line)
  eq(nil, row.ext)
  eq(nil, row.folder)
  eq(nil, row.has_frontmatter)
  eq(nil, row.frontmatter_end_line)
  eq("custom-note", row.id)
  eq(nil, row.aliases)
  eq({ { anchor = "#note", header = "Note", level = 1, line = 5 } }, row.headings)
  eq(nil, row.links_out)
  eq(nil, row.tasks)
end

T["cache backends"]["computes backlink counts from cached links"] = function()
  local dir = Path.temp { suffix = "-obsidian-cache" }
  dir:mkdir { parents = true }
  local note_path = tostring(dir / "A.md")
  helpers.write("# A", note_path)
  helpers.write("[[A]] [[A|alias]] [A](A.md) [root](/A.md) [[Other]]", dir / "Links.md")
  Obsidian = { dir = dir }

  local cache = require "obsidian.cache"
  cache.setup { enabled = true, backend = "memory" }
  vim.wait(1000, function()
    return cache.is_ready()
  end)

  local note = require("obsidian.note").new("A", {}, {}, note_path)
  note.backlinks_async = function()
    error "backlink search should not run"
  end
  local status
  note:status(true, function(result)
    status = result
  end)

  eq(4, cache.notes.backlink_count(note))
  eq(4, status.backlinks)
end

T["cache backends"]["queries headings with original text and locations"] = function()
  local dir = Path.temp { suffix = "-obsidian-cache" }
  dir:mkdir { parents = true }
  helpers.write("# HTTP API Guide\n\nSubtitle\n--------", dir / "Guide.md")
  helpers.write("# Other", dir / "Other.md")
  Obsidian = { dir = dir }

  local cache = require "obsidian.cache"
  cache.setup { enabled = true, backend = "memory" }
  vim.wait(1000, function()
    return cache.is_ready()
  end)

  eq({
    {
      anchor = "#http-api-guide",
      header = "HTTP API Guide",
      level = 1,
      line = 1,
      path = tostring(dir / "Guide.md"),
    },
  }, cache.notes.find_headings "api")
  eq("Subtitle", cache.notes.find_headings("subtitle")[1].header)
  eq(3, cache.notes.find_headings("subtitle")[1].line)
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

  local store = { data = { [vim.fs.normalize(note_path)] = { tags = { "stale" } } } }
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
  helpers.write('{"nodes":[]}', dir / "Board.canvas")
  Obsidian = { dir = dir }

  local cache = require "obsidian.cache"
  cache.setup { enabled = true, backend = "memory" }
  vim.wait(1000, function()
    return cache.is_ready()
  end)

  eq(5, cache.notes.count())
  eq(true, cache.notes.find(tostring(dir / "Page.markdown")) ~= nil)
  eq(true, cache.notes.find(tostring(dir / "Query.qmd")) ~= nil)
  eq(true, cache.notes.find(tostring(dir / "Base.base")) ~= nil)
  eq("canvas", cache.notes.find(tostring(dir / "Board.canvas")).kind)
end

T["cache backends"]["publishes snapshots and indexed symbols"] = function()
  local dir = Path.temp { suffix = "-obsidian-cache" }
  dir:mkdir { parents = true }
  local note_path = tostring(dir / "Project.md")
  helpers.write("---\nid: project-id\naliases: [Roadmap]\n---\n# Project", note_path)
  Obsidian = { dir = dir }

  local cache = require "obsidian.cache"
  cache.setup { enabled = true, backend = "memory" }
  vim.wait(1000, function()
    return cache.is_ready()
  end)

  local snapshot = cache.notes.snapshot()
  eq(true, snapshot.generation > 0)
  eq("Project.md", snapshot.rows[note_path].relative_path)
  eq(note_path, cache.notes.symbols({ query = "road" })[1].path)
  eq(note_path, cache.notes.symbols({ query = "project-id", exact = true })[1].path)

  helpers.write("---\naliases: [Launch]\n---\n# Project", note_path)
  cache.notes.refresh(note_path)
  eq(0, #cache.notes.symbols { query = "Roadmap" })
  eq(note_path, cache.notes.symbols({ query = "Launch" })[1].path)
  eq(true, cache.generation() > snapshot.generation)
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

T["cache backends"]["rebuild command reparses unchanged file stats"] = function()
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

  eq({ "one" }, cache.notes.get(note_path).tags)
  helpers.write("#two", note_path)

  require "obsidian.commands.rebuild_cache"()

  eq({ "two" }, cache.notes.get(note_path).tags)
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
