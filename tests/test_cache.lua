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
      opened = opts.vault == tostring(dir) and opts.path == tostring(dir / ".cache.json")
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
  eq(tostring(new_path), cache.notes.find(tostring(new_path)).path)
end

return T
