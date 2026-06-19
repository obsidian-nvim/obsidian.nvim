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

T["cache backends"]["stores compact rows"] = function()
  local dir = Path.temp { suffix = "-obsidian-cache" }
  dir:mkdir { parents = true }
  local note_path = tostring(dir / "Note.md")
  helpers.write("---\ntags: [Foo]\n---\n# Note", note_path)
  Obsidian = { dir = dir }

  local cache = require "obsidian.cache"
  cache.setup { enabled = true, backend = "memory" }
  vim.wait(1000, function()
    return cache.is_ready()
  end)

  local row = cache.notes.find(note_path)
  eq({ "foo" }, row.tags)
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

return T
