local Async = require "obsidian.async"
local Note = require "obsidian.note"
local Path = require "obsidian.path"
local fs_util = require "obsidian.util.fs"

local M = {}

local reserved_fields = {
  added_at = true,
  imported_at = true,
  removed_at = true,
  resource_id = true,
  revision = true,
  status = true,
  synced_at = true,
  title = true,
  updated_at = true,
  url = true,
  vault = true,
}

local function now()
  return os.date "!%Y-%m-%dT%H:%M:%SZ"
end

local function call_async(fn, args, callback)
  local called = false
  local function done(...)
    if called then
      return
    end
    called = true
    if vim.in_fast_event() then
      local values = vim.F.pack_len(...)
      vim.schedule(function()
        callback(unpack(values, 1, values.n))
      end)
    else
      callback(...)
    end
  end
  args[#args + 1] = done
  local ok, err = pcall(fn, unpack(args))
  if not ok then
    done(tostring(err))
  end
end

---@async
---@param vault obsidian.remote_vault.Vault
---@param ctx obsidian.remote_vault.Context
---@return string?, obsidian.remote_vault.ResourceSummary[]?
local function list_remote(vault, ctx)
  return Async.await(2, function(context, done)
    call_async(vault.list, { context }, done)
  end, ctx)
end

---@async
---@param vault obsidian.remote_vault.Vault
---@param summary obsidian.remote_vault.ResourceSummary
---@param ctx obsidian.remote_vault.Context
---@return string?, obsidian.remote_vault.Resource?
local function fetch_remote(vault, summary, ctx)
  return Async.await(3, function(item, context, done)
    call_async(vault.fetch, { item, context }, done)
  end, summary, ctx)
end

local function validate_summaries(items)
  if type(items) ~= "table" or not vim.islist(items) then
    error("remote vault list callback must return a list", 0)
  end

  local seen = {}
  for i, item in ipairs(items) do
    if type(item) ~= "table" or type(item.id) ~= "string" or item.id == "" then
      error(string.format("remote vault item %d has no non-empty string id", i), 0)
    elseif seen[item.id] then
      error(string.format("remote vault returned duplicate id %q", item.id), 0)
    end
    seen[item.id] = true
  end
end

local function body(note)
  local lines = {}
  for i = (note.frontmatter_end_line or 0) + 1, #note.contents do
    lines[#lines + 1] = note.contents[i]
  end
  return lines
end

local function buffer_state(path)
  local normalized = vim.fs.normalize(tostring(path))
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr)) == normalized then
      return vim.bo[bufnr].modified and "modified" or "loaded"
    end
  end
end

local function index_local(vault, ctx)
  local indexed = {}
  if not ctx.root:is_dir() then
    return indexed
  end

  local archive_root = Path.new(ctx.root / vault.archive_dir):resolve()
  local paths = vim.fs.find(function(name)
    return vim.endswith(name, ".md")
  end, { type = "file", path = tostring(ctx.root), limit = math.huge })

  for _, filename in ipairs(paths) do
    local path = Path.new(filename):resolve()
    if not fs_util.is_subpath(tostring(path), tostring(archive_root)) then
      local note = Note.from_file(path, { max_lines = 2147483647 })
      local metadata = note.metadata or {}
      if metadata.vault == vault.name and metadata.status ~= "removed" then
        local id = metadata.resource_id
        if type(id) ~= "string" or id == "" then
          error(string.format("managed note %s has no resource_id", path), 0)
        elseif indexed[id] then
          error(string.format("resource id %q is claimed by both %s and %s", id, indexed[id].path, path), 0)
        end
        indexed[id] = { path = path, note = note, revision = metadata.revision }
      end
    end
  end
  return indexed
end

---@class obsidian.remote_vault.Plan
---@field create obsidian.remote_vault.ResourceSummary[]
---@field update { summary: obsidian.remote_vault.ResourceSummary, local_item: table }[]
---@field unchanged { summary: obsidian.remote_vault.ResourceSummary, local_item: table }[]
---@field remove table[]

---Build a side-effect-free sync plan.
---@param summaries obsidian.remote_vault.ResourceSummary[]
---@param local_items table<string, table>
---@param opts? { force: boolean? }
---@return obsidian.remote_vault.Plan
function M.plan(summaries, local_items, opts)
  opts = opts or {}
  local plan = { create = {}, update = {}, unchanged = {}, remove = {} }
  local present = {}

  for _, summary in ipairs(summaries) do
    present[summary.id] = true
    local local_item = local_items[summary.id]
    if not local_item then
      plan.create[#plan.create + 1] = summary
    elseif opts.force or summary.revision == nil or summary.revision ~= local_item.revision then
      plan.update[#plan.update + 1] = { summary = summary, local_item = local_item }
    else
      plan.unchanged[#plan.unchanged + 1] = { summary = summary, local_item = local_item }
    end
  end

  for id, local_item in pairs(local_items) do
    if not present[id] then
      plan.remove[#plan.remove + 1] = local_item
    end
  end
  table.sort(plan.remove, function(a, b)
    return tostring(a.path) < tostring(b.path)
  end)
  return plan
end

local function resource_path(vault, resource, ctx)
  local relative = Path.new(vault.note_path(resource, ctx))
  assert(not relative:is_absolute(), "remote vault path callback must return a relative path")
  if relative.suffix ~= ".md" then
    relative = relative:with_suffix(".md", true)
  end
  local path = (ctx.root / relative):resolve()
  assert(fs_util.is_subpath(tostring(path), tostring(ctx.root)), "remote vault path escapes its configured directory")
  return path
end

---@return obsidian.Path
local function apply_resource(vault, summary, resource, local_item, ctx, synced_at)
  if type(resource) ~= "table" then
    error(string.format("fetch for %q did not return a resource", summary.id), 0)
  end
  resource = vim.tbl_extend("keep", vim.deepcopy(resource), summary)
  if resource.id ~= summary.id then
    error(string.format("fetch for %q returned id %q", summary.id, tostring(resource.id)), 0)
  end

  local path = local_item and local_item.path or resource_path(vault, resource, ctx)
  if local_item and buffer_state(path) == "modified" then
    error(string.format("refusing to overwrite modified buffer %s", path), 0)
  elseif not local_item and path:exists() then
    error(string.format("refusing to overwrite unmanaged note %s", path), 0)
  end

  local note = local_item and local_item.note or Note.new(path.stem, {}, { "remote-resource" }, path, resource.title)
  local current_body = local_item and body(note) or {}
  local rendered = vault.render(resource, current_body, ctx)
  assert(type(rendered) == "table" and vim.islist(rendered), "remote vault render callback must return a list of lines")

  note.metadata = note.metadata or {}
  if type(resource.metadata) == "table" then
    for key, value in pairs(resource.metadata) do
      if not reserved_fields[key] then
        note.metadata[key] = value
      end
    end
  end
  if vault.frontmatter then
    local extra = vault.frontmatter(resource, ctx)
    if extra ~= nil then
      assert(type(extra) == "table", "remote vault frontmatter callback must return a table or nil")
      for key, value in pairs(extra) do
        if not reserved_fields[key] then
          note.metadata[key] = value
        end
      end
    end
  end

  note.metadata.vault = vault.name
  note.metadata.resource_id = resource.id
  note.metadata.url = resource.url
  note.metadata.title = resource.title
  note.metadata.revision = resource.revision
  note.metadata.added_at = resource.added_at
  note.metadata.updated_at = resource.updated_at
  note.metadata.imported_at = note.metadata.imported_at or synced_at
  note.metadata.synced_at = synced_at
  note.metadata.status = "active"
  note.metadata.removed_at = nil

  note:save {
    insert_frontmatter = true,
    update_content = function()
      return rendered
    end,
  }
  return path
end

---@return "archived"|"deleted"|"kept"
---@return obsidian.Path
local function remove_resource(vault, local_item, ctx, synced_at)
  local path = local_item.path
  if vault.removal == "keep" then
    return "kept", path
  end

  local state = buffer_state(path)
  if state then
    error(string.format("refusing to %s note with a %s buffer: %s", vault.removal, state, path), 0)
  end

  if vault.removal == "delete" then
    local ok, err = os.remove(tostring(path))
    assert(ok, err)
    return "deleted", path
  end

  local note = local_item.note
  note.metadata.status = "removed"
  note.metadata.removed_at = synced_at
  note.metadata.synced_at = synced_at
  note:save { insert_frontmatter = true }

  local relative = path:relative_to(ctx.root)
  local destination = Path.new(ctx.root / vault.archive_dir / relative):resolve()
  assert(fs_util.is_subpath(tostring(destination), tostring(ctx.root)), "archive path escapes remote vault directory")
  assert(not destination:exists(), "archive destination already exists: " .. tostring(destination))
  assert(destination:parent()):mkdir { parents = true }
  local ok, err = vim.uv.fs_rename(tostring(path), tostring(destination))
  assert(ok, err)
  return "archived", destination
end

---@class obsidian.remote_vault.Report
---@field name string
---@field plan obsidian.remote_vault.Plan
---@field created obsidian.Path[]
---@field updated obsidian.Path[]
---@field archived obsidian.Path[]
---@field deleted obsidian.Path[]
---@field kept obsidian.Path[]
---@field errors string[]
---@field dry_run boolean

---Run one remote vault sync.
---@param vault obsidian.remote_vault.Vault
---@param opts? { force: boolean?, dry_run: boolean? }
---@param on_finish? fun(err: string?, report: obsidian.remote_vault.Report?)
---@return table task
function M.run(vault, opts, on_finish)
  opts = opts or {}
  local ctx = vault:context()

  return Async.run(function()
    local list_err, summaries = list_remote(vault, ctx)
    if list_err then
      error(tostring(list_err), 0)
    end
    validate_summaries(summaries)
    ---@cast summaries obsidian.remote_vault.ResourceSummary[]

    local local_items = index_local(vault, ctx)
    local plan = M.plan(summaries, local_items, { force = opts.force })
    ---@type obsidian.remote_vault.Report
    local report = {
      name = vault.name,
      plan = plan,
      created = {},
      updated = {},
      archived = {},
      deleted = {},
      kept = {},
      errors = {},
      dry_run = opts.dry_run == true,
    }
    if opts.dry_run then
      return report
    end

    local synced_at = now()
    local operations = {}
    for _, summary in ipairs(plan.create) do
      operations[#operations + 1] = { kind = "created", summary = summary }
    end
    for _, operation in ipairs(plan.update) do
      operations[#operations + 1] = {
        kind = "updated",
        summary = operation.summary,
        local_item = operation.local_item,
      }
    end

    for _, operation in ipairs(operations) do
      local fetch_err, resource = fetch_remote(vault, operation.summary, ctx)
      if fetch_err then
        report.errors[#report.errors + 1] = string.format("%s: %s", operation.summary.id, fetch_err)
      else
        local ok, path_or_err =
          pcall(apply_resource, vault, operation.summary, resource, operation.local_item, ctx, synced_at)
        if ok then
          if operation.kind == "created" then
            report.created[#report.created + 1] = path_or_err
          else
            report.updated[#report.updated + 1] = path_or_err
          end
        else
          report.errors[#report.errors + 1] = string.format("%s: %s", operation.summary.id, path_or_err)
        end
      end
    end

    -- A partial import must never be followed by destructive cleanup.
    if #report.errors == 0 then
      for _, local_item in ipairs(plan.remove) do
        local ok, kind, path_or_err = pcall(remove_resource, vault, local_item, ctx, synced_at)
        if ok then
          if kind == "archived" then
            report.archived[#report.archived + 1] = path_or_err
          elseif kind == "deleted" then
            report.deleted[#report.deleted + 1] = path_or_err
          else
            report.kept[#report.kept + 1] = path_or_err
          end
        else
          report.errors[#report.errors + 1] = string.format("%s: %s", local_item.path, kind)
        end
      end
    end

    return report
  end, on_finish)
end

return M
