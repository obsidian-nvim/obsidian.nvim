local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local helpers = require "tests.helpers"
local Note = require "obsidian.note"
local Path = require "obsidian.path"
local Sync = require "obsidian.remote-vault.sync"
local Vault = require("obsidian.remote-vault.vault").Vault
local Workspace = require "obsidian.workspace"

local T = new_set()

local function adapter(spec)
  spec = vim.tbl_extend("force", {
    name = "reading-list",
    path = Path.temp { suffix = "-remote-vault" },
    list = function(_, callback)
      callback(nil, {})
    end,
    fetch = function(summary, _, callback)
      callback(nil, summary)
    end,
  }, spec or {})
  local vault = Vault.new(spec)
  vault.path:mkdir { parents = true }
  vault.workspace = assert(Workspace.new {
    path = vault.path,
    name = vault.name,
    strict = true,
  })
  return vault
end

T["plan classifies resources without side effects"] = function()
  local summaries = {
    { id = "new", revision = "1" },
    { id = "changed", revision = "2" },
    { id = "same", revision = "1" },
    { id = "unknown" },
  }
  local locals = {
    changed = { revision = "1", path = "changed.md" },
    same = { revision = "1", path = "same.md" },
    unknown = { revision = nil, path = "unknown.md" },
    gone = { revision = "1", path = "gone.md" },
  }

  local plan = Sync.plan(summaries, locals)
  eq(
    { "new" },
    vim.tbl_map(function(item)
      return item.id
    end, plan.create)
  )
  eq(
    { "changed", "unknown" },
    vim.tbl_map(function(item)
      return item.summary.id
    end, plan.update)
  )
  eq(
    { "same" },
    vim.tbl_map(function(item)
      return item.summary.id
    end, plan.unchanged)
  )
  eq(
    { "gone.md" },
    vim.tbl_map(function(item)
      return item.path
    end, plan.remove)
  )
end

T["vault validates removal strategy"] = function()
  local ok, err = pcall(adapter, { removal = "explode" })
  eq(false, ok)
  eq(true, tostring(err):find("archive", 1, true) ~= nil)
end

T["vault requires an absolute path"] = function()
  local ok, err = pcall(adapter, { path = "Resources/Reading" })
  eq(false, ok)
  eq(true, tostring(err):find("absolute", 1, true) ~= nil)
end

local Integration = helpers.temp_vault
T["sync lifecycle"] = Integration

Integration["materializes, updates, and archives resources"] = function()
  local summaries = {
    {
      id = "article-1",
      revision = "1",
      title = "First title",
      url = "https://example.test/1",
      added_at = "2026-01-01T00:00:00Z",
    },
  }
  local fetches = 0
  local vault = adapter {
    list = function(_, callback)
      callback(nil, vim.deepcopy(summaries))
    end,
    fetch = function(summary, _, callback)
      fetches = fetches + 1
      callback(
        nil,
        vim.tbl_extend("force", summary, {
          content = { "# " .. summary.title, "", "Remote body " .. summary.revision },
          metadata = { provider = "test" },
        })
      )
    end,
  }

  local first = Sync.run(vault):wait()
  eq(1, #first.created)
  eq(1, fetches)

  local path = first.created[1]
  eq(true, vault.path:is_parent_of(path))
  eq(false, Obsidian.dir:is_parent_of(path))
  local note = Note.from_file(path, { max_lines = math.huge })
  eq("reading-list", note.metadata.vault)
  eq("article-1", note.metadata.resource_id)
  eq("https://example.test/1", note.metadata.url)
  eq("test", note.metadata.provider)
  eq("active", note.metadata.status)
  eq("# First title", note.contents[note.frontmatter_end_line + 1])
  local imported_at = note.metadata.imported_at

  local unchanged = Sync.run(vault):wait()
  eq(1, #unchanged.plan.unchanged)
  eq(1, fetches)

  summaries[1].revision = "2"
  summaries[1].title = "Renamed title"
  local updated = Sync.run(vault):wait()
  eq(1, #updated.updated)
  eq(tostring(path), tostring(updated.updated[1]))
  eq(2, fetches)

  note = Note.from_file(path, { max_lines = math.huge })
  eq("# Renamed title", note.contents[note.frontmatter_end_line + 1])
  eq(imported_at, note.metadata.imported_at)

  summaries = {}
  local removed = Sync.run(vault):wait()
  eq(1, #removed.archived)
  eq(false, Path.new(path):exists())
  eq(true, removed.archived[1]:is_file())

  local archived = Note.from_file(removed.archived[1], { max_lines = math.huge })
  eq("removed", archived.metadata.status)
  eq(true, archived.metadata.removed_at ~= nil)
  vim.fn.delete(tostring(vault.path), "rf")
end

Integration["registration injects a separate workspace"] = function()
  local remote = require "obsidian.remote-vault"
  local root = Path.temp { suffix = "-registered-remote-vault" }
  local current = Obsidian.workspace
  local count = #Obsidian.workspaces
  local vault = remote.register {
    name = "registered-reading-list",
    path = root,
    list = function(_, callback)
      callback(nil, {})
    end,
    fetch = function(summary, _, callback)
      callback(nil, summary)
    end,
  }

  eq(count + 1, #Obsidian.workspaces)
  eq(current, Obsidian.workspace)
  eq(vault.workspace, Obsidian.workspaces[#Obsidian.workspaces])
  eq(root:resolve(), vault.workspace.root)
  eq(vault.workspace, require("obsidian.api").find_workspace(root))

  local ok, err = pcall(remote.register, {
    name = "overlapping-reading-list",
    path = Obsidian.dir / "nested",
    list = function(_, callback)
      callback(nil, {})
    end,
    fetch = function(summary, _, callback)
      callback(nil, summary)
    end,
  })
  eq(false, ok)
  eq(true, tostring(err):find("overlaps", 1, true) ~= nil)
  vim.fn.delete(tostring(root), "rf")
end

Integration["failed fetch prevents removals"] = function()
  local vault = adapter {
    removal = "delete",
    list = function(_, callback)
      callback(nil, { { id = "new", revision = "1" } })
    end,
    fetch = function(_, _, callback)
      callback "provider unavailable"
    end,
  }
  local old_path = vault.path / "old.md"
  local old = Note.new("old", {}, {}, old_path)
  old.metadata = {
    vault = "reading-list",
    resource_id = "old",
    revision = "1",
    status = "active",
  }
  old:save {
    insert_frontmatter = true,
    update_content = function()
      return { "old" }
    end,
  }

  local report = Sync.run(vault):wait()
  eq(1, #report.errors)
  eq(true, old_path:is_file())
  eq(0, #report.deleted)
  vim.fn.delete(tostring(vault.path), "rf")
end

return T
