local Path = require "obsidian.path"
local fs_util = require "obsidian.util.fs"

local M = {}

local removal_strategies = { archive = true, delete = true, keep = true }

local function default_path(resource)
  local slug = vim.trim(vim.fn.tolower(resource.title or ""))
  slug = vim.fn.substitute(slug, "[^[:keyword:][:space:]-]", "", "g")
  slug = vim.fn.substitute(slug, "[_[:space:]]\\+", "-", "g")
  slug = vim.fn.substitute(slug, "-\\+", "-", "g"):gsub("^-", ""):gsub("-$", "")
  if slug == "" then
    slug = "resource"
  end
  return string.format("%s--%s.md", slug, vim.fn.sha256(resource.id):sub(1, 10))
end

local function default_render(resource, current_body)
  if type(resource.content) == "table" then
    return vim.deepcopy(resource.content)
  elseif type(resource.content) == "string" then
    return vim.split(resource.content, "\n", { plain = true })
  elseif current_body and #current_body > 0 then
    return current_body
  end

  local lines = { "# " .. (resource.title or resource.id) }
  if resource.url then
    vim.list_extend(lines, { "", resource.url })
  end
  return lines
end

---@class obsidian.remote_vault.ResourceSummary
---@field id string Stable, provider-scoped identifier.
---@field revision? string Changes whenever content or metadata relevant to the note changes.
---@field title? string
---@field url? string
---@field added_at? string
---@field updated_at? string
---@field data? any Opaque adapter data forwarded to `fetch`.

---@class obsidian.remote_vault.Resource : obsidian.remote_vault.ResourceSummary
---@field content? string|string[] Complete provider-owned note body.
---@field metadata? table<string, any> Additional frontmatter fields.

---@class obsidian.remote_vault.Context
---@field vault obsidian.remote_vault.Vault
---@field workspace obsidian.Workspace
---@field root obsidian.Path

---@alias obsidian.remote_vault.Callback fun(err: string?, value: any?)

---@class obsidian.remote_vault.Spec
---@field name string Command-facing unique name and injected workspace name.
---@field path string|obsidian.Path Absolute workspace root for this remote vault.
---@field list fun(ctx: obsidian.remote_vault.Context, callback: obsidian.remote_vault.Callback)
---@field fetch fun(summary: obsidian.remote_vault.ResourceSummary, ctx: obsidian.remote_vault.Context, callback: obsidian.remote_vault.Callback)
---@field note_path? fun(resource: obsidian.remote_vault.Resource, ctx: obsidian.remote_vault.Context): string|obsidian.Path Path relative to the remote workspace root.
---@field render? fun(resource: obsidian.remote_vault.Resource, current_body: string[], ctx: obsidian.remote_vault.Context): string[]
---@field frontmatter? fun(resource: obsidian.remote_vault.Resource, ctx: obsidian.remote_vault.Context): table<string, any>?
---@field removal? "archive"|"delete"|"keep"
---@field archive_dir? string Directory relative to the remote workspace root.

---@class obsidian.remote_vault.Vault
---@field name string
---@field path obsidian.Path
---@field workspace? obsidian.Workspace Set when the vault is registered.
---@field list fun(ctx: obsidian.remote_vault.Context, callback: obsidian.remote_vault.Callback)
---@field fetch fun(summary: obsidian.remote_vault.ResourceSummary, ctx: obsidian.remote_vault.Context, callback: obsidian.remote_vault.Callback)
---@field note_path fun(resource: obsidian.remote_vault.Resource, ctx: obsidian.remote_vault.Context): string|obsidian.Path
---@field render fun(resource: obsidian.remote_vault.Resource, current_body: string[], ctx: obsidian.remote_vault.Context): string[]
---@field frontmatter? fun(resource: obsidian.remote_vault.Resource, ctx: obsidian.remote_vault.Context): table<string, any>?
---@field removal "archive"|"delete"|"keep"
---@field archive_dir obsidian.Path
local Vault = {}
Vault.__index = Vault

---@param spec obsidian.remote_vault.Spec
---@return obsidian.remote_vault.Vault
function Vault.new(spec)
  vim.validate {
    spec = { spec, "table", false },
    name = { spec and spec.name, "string", false },
    path = { spec and spec.path, { "string", "table" }, false },
    list = { spec and spec.list, "callable", false },
    fetch = { spec and spec.fetch, "callable", false },
    note_path = { spec and spec.note_path, "callable", true },
    render = { spec and spec.render, "callable", true },
    frontmatter = { spec and spec.frontmatter, "callable", true },
  }
  assert(spec.name ~= "", "remote vault name cannot be empty")

  local removal = spec.removal or "archive"
  if not removal_strategies[removal] then
    error "remote vault removal must be 'archive', 'delete', or 'keep'"
  end

  local path = Path.new(spec.path)
  assert(path:is_absolute(), "remote vault path must be absolute")

  return setmetatable({
    name = spec.name,
    path = path:resolve(),
    list = spec.list,
    fetch = spec.fetch,
    note_path = spec.note_path or default_path,
    render = spec.render or default_render,
    frontmatter = spec.frontmatter,
    removal = removal,
    archive_dir = Path.new(spec.archive_dir or "_archive"),
  }, Vault)
end

---@return obsidian.remote_vault.Context
function Vault:context()
  local workspace = assert(self.workspace, "remote vault must be registered before syncing")
  local root = workspace.root
  assert(not self.archive_dir:is_absolute(), "remote vault archive_dir must be relative")
  local archive_root = (root / self.archive_dir):resolve()
  assert(fs_util.is_subpath(tostring(archive_root), tostring(root)), "remote vault archive_dir escapes its workspace")
  return { vault = self, workspace = workspace, root = root }
end

M.Vault = Vault
M.new = Vault.new

return M
