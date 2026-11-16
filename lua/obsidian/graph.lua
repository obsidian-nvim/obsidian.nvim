---Storage-independent, on-disk vault graph snapshots. No renderer or watchers.
---Rebuild a snapshot after files/cache rows change. Public results are copies.
local filetypes = require "obsidian.filetypes"
local tag = require "obsidian.tag"

---@alias obsidian.graph.NodeType "note"|"attachment"|"tag"|"missing"
---@alias obsidian.graph.References table<string, string[]>

---@class obsidian.graph.Node
---@field id string Namespaced identity; file IDs retain the vault-relative extension.
---@field type obsidian.graph.NodeType
---@field title string
---@field path string?
---@field folder string
---@field aliases string[]
---@field tags string[]
---@field exists boolean

---@class obsidian.graph.Link
---@field source string
---@field target string

---@class obsidian.graph.BrokenLink
---@field source string Source note node ID.
---@field path string Absolute source path.
---@field target string Target as written in the source.
---@field kind string?
---@field raw string?
---@field line integer?
---@field col integer?
---@field candidates? string[] Present only for ambiguous references.

---@class obsidian.graph.AmbiguousLink : obsidian.graph.BrokenLink
---@field candidates string[] Candidate node IDs, sorted by identity.

---@class obsidian.graph.Table
---@field nodes obsidian.graph.Node[]
---@field links obsidian.graph.Link[]

---@class obsidian.graph.RenderOpts
---@field include_tag_nodes? boolean Defaults to false. Attachments are always included.

---@class obsidian.graph.OrphanOpts
---@field include_tag_nodes? boolean Count tag memberships as connections. Defaults to false.
---@field include_attachments? boolean Also return unreferenced attachment paths. Defaults to false.

---@class obsidian.graph.LoadOpts
---@field dir? string|obsidian.Path Vault root. Defaults to the active workspace root.

---@class obsidian.graph.Entry : obsidian.graph.Node
---@field path string
---@field rel string Vault-relative path, including extension.
---@field links_out table[]

---@class obsidian.graph.UnresolvedLink
---@field entry obsidian.graph.Entry
---@field link table
---@field target string Expected vault-relative path.
---@field type "note"|"attachment"
---@field candidates string[]

---@class obsidian.graph.Analysis
---@field links obsidian.graph.Link[]
---@field broken obsidian.graph.UnresolvedLink[]
---@field ambiguous obsidian.graph.UnresolvedLink[]
---@field connected table<string, boolean>

---@class obsidian.Graph
---@field _entries obsidian.graph.Entry[]
---@field _by_id table<string, obsidian.graph.Entry>
---@field _paths table<string, string>
---@field _folded_paths obsidian.graph.References
---@field _note_refs obsidian.graph.References
---@field _attachment_refs obsidian.graph.References
---@field _attachment_folder string
---@field _vault string
---@field _analysis obsidian.graph.Analysis?
local Graph = {}
Graph.__index = Graph

---@param path string
---@return string
local function folder(path)
  return path:match "^(.*)/[^/]+$" or ""
end

---@param path string
---@return string
local function basename(path)
  return path:match "([^/]+)$" or path
end

---@param path string
---@return string
local function note_stem(path)
  return (path:gsub("%.[^./]+$", ""))
end

---Normalize a vault-relative path, rejecting paths which escape the vault.
---@param path string
---@return string?
local function normalize_path(path)
  local parts = {}
  for part in path:gsub("\\", "/"):gmatch "[^/]+" do
    if part == ".." then
      if #parts == 0 then
        return nil
      end
      parts[#parts] = nil
    elseif part ~= "." then
      parts[#parts + 1] = part
    end
  end
  return table.concat(parts, "/")
end

---@param base string
---@param path string
---@return string?
local function join(base, path)
  return normalize_path(base ~= "" and (base .. "/" .. path) or path)
end

---@param value any
---@return string[]
local function string_list(value)
  local out = {}
  for _, item in ipairs(type(value) == "table" and value or {}) do
    if type(item) == "string" and item ~= "" then
      out[#out + 1] = item
    end
  end
  return out
end

---@param value any
---@return string[]
local function tag_list(value)
  local out, seen = {}, {}
  for _, raw in ipairs(string_list(value)) do
    local name = tag.normalize(raw)
    if name ~= "" and not seen[name] then
      out[#out + 1] = name
      seen[name] = true
    end
  end
  table.sort(out)
  return out
end

---@param refs obsidian.graph.References
---@param ref string
---@param id string
local function add_reference(refs, ref, id)
  ref = vim.fn.tolower(vim.trim(ref))
  if ref == "" then
    return
  end
  refs[ref] = refs[ref] or {}
  if not vim.tbl_contains(refs[ref], id) then
    refs[ref][#refs[ref] + 1] = id
    table.sort(refs[ref])
  end
end

---@param row table
---@param fallback string
---@return string
local function note_title(row, fallback)
  if type(row.properties) == "table" and type(row.properties.title) == "string" and row.properties.title ~= "" then
    return row.properties.title
  elseif type(row.id) == "string" and row.id ~= "" then
    return row.id
  end
  return fallback
end

---@param rows table<string, table>
---@param relative fun(path: string): string
---@param attachment_folder string
---@param vault string
---@return obsidian.Graph
local function build(rows, relative, attachment_folder, vault)
  local self = setmetatable({
    _entries = {},
    _by_id = {},
    _paths = {},
    _folded_paths = {},
    _note_refs = {},
    _attachment_refs = {},
    _attachment_folder = attachment_folder,
    _vault = vault,
  }, Graph)

  for path, row in pairs(rows) do
    local rel = assert(normalize_path(relative(path)))
    local kind = row.kind or "note"
    local id = kind .. ":" .. rel
    local entry = {
      id = id,
      type = kind,
      path = path,
      rel = rel,
      folder = folder(rel),
      title = kind == "note" and note_title(row, note_stem(basename(rel))) or basename(rel),
      aliases = string_list(row.aliases),
      tags = tag_list(row.tags),
      links_out = vim.deepcopy(row.links_out or {}),
      exists = true,
    }
    self._entries[#self._entries + 1] = entry
    self._by_id[id] = entry
    self._paths[rel] = id
    add_reference(self._folded_paths, rel, id)

    if kind == "note" then
      add_reference(self._note_refs, basename(rel), id)
      -- Bases require an explicit extension, as in normal note resolution.
      if filetypes.extension(rel) ~= "base" then
        add_reference(self._note_refs, note_stem(basename(rel)), id)
        if type(row.id) == "string" or type(row.id) == "number" then
          add_reference(self._note_refs, tostring(row.id), id)
        end
        for _, alias in ipairs(entry.aliases) do
          add_reference(self._note_refs, alias, id)
        end
      end
    else
      add_reference(self._attachment_refs, basename(rel), id)
    end
  end
  table.sort(self._entries, function(a, b)
    return a.id < b.id
  end)
  return self
end

---Create a snapshot from the ready cache, without reading the filesystem.
---@return obsidian.Graph
function Graph.from_cache()
  local cache = require "obsidian.cache"
  ---@type table<string, table>
  local rows = cache.notes.all()
  for path, row in pairs(cache.attachments.all()) do
    rows[path] = row
  end
  return build(
    rows,
    cache.notes.rel_path,
    Obsidian.opts.attachments.folder or "",
    vim.fs.normalize(tostring(Obsidian.dir))
  )
end

---Build an on-disk snapshot using rg file enumeration (filesystem fallback).
---Reads complete notes, not search.max_lines-limited excerpts. Unsaved buffers
---are deliberately excluded, just as in from_cache(). An error returns no graph.
---@param callback fun(graph: obsidian.Graph?, err: string?)
---@param opts obsidian.graph.LoadOpts?
---@return fun() cancel Suppress the callback and stop pending work.
function Graph.from_vault_async(callback, opts)
  opts = opts or {}
  local api = require "obsidian.api"
  local vault =
    vim.fs.normalize(tostring(require("obsidian.path").new(opts.dir or api.resolve_workspace_dir()):resolve()))
  local stat = vim.uv.fs_stat(vault)
  if not stat or stat.type ~= "directory" then
    local cancelled = false
    vim.schedule(function()
      if not cancelled then
        callback(nil, "graph: not a vault directory: " .. vault)
      end
    end)
    return function()
      cancelled = true
    end
  end
  local workspace = api.find_workspace(vault)
  local config = workspace and api._workspace_opts(workspace) or Obsidian.opts
  local attachment_folder = config.attachments.folder or ""
  return require("obsidian.graph.scan").scan(vault, {
    config_dir = config.sync.config_dir or ".obsidian",
    ignore_checker = require("obsidian.ignore")._build_ignore_checker(config.file.ignore_filters or {}),
  }, function(rows, err)
    if not rows then
      callback(nil, err)
      return
    end
    callback(build(rows, function(path)
      return path:sub(#vault + 2)
    end, attachment_folder, vault))
  end)
end

---@param self obsidian.Graph
---@param target any
---@return string?
local function normalize_target(self, target)
  if type(target) ~= "string" then
    return nil
  end
  target = vim.trim(target)
  if target:sub(1, 1) == "<" and target:sub(-1) == ">" then
    target = target:sub(2, -2)
  end
  if target == "" or target:sub(1, 1) == "#" then
    return nil
  end
  local uri = require "obsidian.uri"
  local scheme = uri.scheme(target)
  if scheme and scheme ~= "file" then
    return nil
  end
  local ok, decoded
  if scheme == "file" then
    -- URI fragments are not part of an attachment's filename.
    ok, decoded = pcall(vim.uri_to_fname, (target:gsub("[?#].*$", "")))
  else
    ok, decoded = pcall(vim.uri_decode, target)
  end
  if not ok then
    return nil
  end
  decoded = decoded:gsub("\\", "/")
  local prefix = self._vault:gsub("/+$", "") .. "/"
  if vim.startswith(decoded, prefix) then
    return "/" .. decoded:sub(#prefix + 1)
  elseif scheme == "file" or decoded:match "^%a:/" or uri.is_uri(decoded) then
    return nil
  end
  return decoded
end

---@param self obsidian.Graph
---@param path string
---@param kind "note"|"attachment"
---@return string[]
local function exact_path(self, path, kind)
  local id = self._paths[path]
  if id and self._by_id[id].type == kind then
    return { id }
  end
  local matches = {}
  for _, candidate in ipairs(self._folded_paths[vim.fn.tolower(path)] or {}) do
    if self._by_id[candidate].type == kind then
      matches[#matches + 1] = candidate
    end
  end
  return matches
end

---@param self obsidian.Graph
---@param path string
---@return string[]
local function note_path(self, path)
  if filetypes.is_note(path) then
    return exact_path(self, path, "note")
  end
  local matches = {}
  for _, ext in ipairs(filetypes.note_extensions) do
    if ext ~= "base" then
      vim.list_extend(matches, exact_path(self, path .. "." .. ext, "note"))
    end
  end
  table.sort(matches)
  return matches
end

---@param target string
---@param entry obsidian.graph.Entry
---@return string[]
local function target_candidates(target, entry)
  if vim.startswith(target, "/") then
    local path = normalize_path(target)
    return path and { path } or {}
  end
  local local_path = join(entry.folder, target)
  if vim.startswith(target, "./") or vim.startswith(target, "../") then
    return local_path and { local_path } or {}
  end
  local root_path = normalize_path(target)
  local paths = {}
  if local_path then
    paths[#paths + 1] = local_path
  end
  if root_path and root_path ~= local_path then
    paths[#paths + 1] = root_path
  end
  return paths
end

---@param self obsidian.Graph
---@param target string
---@param entry obsidian.graph.Entry
---@param link table
---@return string[] ids
---@return string? expected_path
local function resolve_note(self, target, entry, link)
  local paths = target_candidates(target, entry)
  for _, path in ipairs(paths) do
    local matches = note_path(self, path)
    if #matches > 0 then
      return matches, path
    end
  end
  -- Paths always beat aliases/IDs/basenames. Explicit relative links never
  -- fall back to a same-named note in a different directory.
  local relative = vim.startswith(target, "./") or vim.startswith(target, "../")
  if not relative and not vim.startswith(target, "/") then
    local matches = self._note_refs[vim.fn.tolower(target)]
    if matches then
      return matches, paths[1]
    end
  end
  local expected = paths[1]
  if link.kind ~= "markdown" and not relative then
    expected = normalize_path(target)
  end
  if expected and not filetypes.is_note(expected) then
    expected = expected .. ".md"
  end
  return {}, expected
end

---@param self obsidian.Graph
---@param target string
---@param entry obsidian.graph.Entry
---@return string[] ids
---@return string? expected_path
local function resolve_attachment(self, target, entry)
  local has_path = target:find "/" ~= nil
  local configured
  if not has_path then
    local base = self._attachment_folder
    configured = vim.startswith(base, ".") and join(entry.folder, base .. "/" .. target) or join(base, target)
    if configured then
      local matches = exact_path(self, configured, "attachment")
      if #matches > 0 then
        return matches, configured
      end
    end
    return self._attachment_refs[vim.fn.tolower(target)] or {}, configured
  end
  -- Attachment navigation treats two existing source/root paths as ambiguous.
  local matches, seen = {}, {}
  local paths = target_candidates(target, entry)
  for _, path in ipairs(paths) do
    for _, id in ipairs(exact_path(self, path, "attachment")) do
      if not seen[id] then
        matches[#matches + 1] = id
        seen[id] = true
      end
    end
  end
  table.sort(matches)
  return matches, paths[1]
end

---@param self obsidian.Graph
---@return obsidian.graph.Analysis
local function analyze(self)
  if self._analysis then
    return self._analysis
  end
  ---@type obsidian.graph.Analysis
  local analysis = { links = {}, broken = {}, ambiguous = {}, connected = {} }
  local link_ids = {}
  for _, entry in ipairs(self._entries) do
    for _, link in ipairs(entry.links_out) do
      local target = normalize_target(self, link.target)
      if target then
        local kind = filetypes.is_attachment(target) and "attachment" or "note"
        local matches, expected
        if kind == "attachment" then
          matches, expected = resolve_attachment(self, target, entry)
        else
          matches, expected = resolve_note(self, target, entry, link)
        end
        if #matches == 1 then
          local resolved = matches[1]
          if resolved ~= entry.id then
            local key = entry.id .. "\0" .. resolved
            if not link_ids[key] then
              analysis.links[#analysis.links + 1] = { source = entry.id, target = resolved }
              link_ids[key] = true
            end
            analysis.connected[entry.id] = true
            analysis.connected[resolved] = true
          end
        elseif #matches > 1 or (expected and (filetypes.kind(target) or filetypes.extension(target) == "")) then
          local unresolved = {
            entry = entry,
            link = link,
            target = expected or target,
            type = kind,
            candidates = matches,
          }
          local list = #matches > 1 and analysis.ambiguous or analysis.broken
          list[#list + 1] = unresolved
        end
      end
    end
  end
  self._analysis = analysis
  return analysis
end

---@param unresolved obsidian.graph.UnresolvedLink
---@return obsidian.graph.BrokenLink
local function diagnostic(unresolved)
  local link = unresolved.link
  return {
    source = unresolved.entry.id,
    path = unresolved.entry.path,
    target = link.target,
    kind = link.kind,
    raw = link.raw,
    line = link.line,
    col = link.col,
  }
end

---@param a obsidian.graph.BrokenLink
---@param b obsidian.graph.BrokenLink
---@return boolean
local function diagnostic_less(a, b)
  if a.path ~= b.path then
    return a.path < b.path
  elseif (a.line or 0) ~= (b.line or 0) then
    return (a.line or 0) < (b.line or 0)
  elseif (a.col or 0) ~= (b.col or 0) then
    return (a.col or 0) < (b.col or 0)
  end
  return a.target < b.target
end

---Return missing internal note and attachment links. Ambiguity is not missing.
---@return obsidian.graph.BrokenLink[]
function Graph:broken_links()
  local result = {}
  for _, broken in ipairs(analyze(self).broken) do
    result[#result + 1] = diagnostic(broken)
  end
  table.sort(result, diagnostic_less)
  return result
end

---Return ambiguous references, without inventing missing nodes for them.
---@return obsidian.graph.AmbiguousLink[]
function Graph:ambiguous_links()
  local result = {}
  for _, ambiguous in ipairs(analyze(self).ambiguous) do
    local item = diagnostic(ambiguous)
    item.candidates = vim.deepcopy(ambiguous.candidates)
    result[#result + 1] = item
  end
  table.sort(result, diagnostic_less)
  return result
end

---Return absolute paths with no resolved incoming or outgoing connections.
---By default only notes are returned. Self-links, missing and ambiguous links
---do not count; resolved attachment links do. Tag memberships are opt-in.
---@param opts obsidian.graph.OrphanOpts?
---@return string[]
function Graph:orphan_files(opts)
  opts = opts or {}
  local analysis = analyze(self)
  local result = {}
  for _, entry in ipairs(self._entries) do
    local connected = analysis.connected[entry.id] or (opts.include_tag_nodes and #entry.tags > 0)
    if not connected and (entry.type == "note" or opts.include_attachments) then
      result[#result + 1] = entry.path
    end
  end
  table.sort(result)
  return result
end

---Materialize detached visualization nodes and deduplicated directed links.
---@param opts obsidian.graph.RenderOpts?
---@return obsidian.graph.Table
function Graph:to_table(opts)
  opts = opts or {}
  local analysis = analyze(self)
  local nodes, node_ids = {}, {}
  local links = vim.deepcopy(analysis.links)
  local function add_node(node)
    if not node_ids[node.id] then
      nodes[#nodes + 1] = node
      node_ids[node.id] = true
    end
  end
  for _, entry in ipairs(self._entries) do
    add_node {
      id = entry.id,
      type = entry.type,
      title = entry.title,
      path = entry.path,
      folder = entry.folder,
      aliases = vim.deepcopy(entry.aliases),
      tags = vim.deepcopy(entry.tags),
      exists = true,
    }
  end
  local missing_links = {}
  for _, broken in ipairs(analysis.broken) do
    local id = "missing:" .. broken.type .. ":" .. broken.target
    add_node {
      id = id,
      type = "missing",
      title = broken.type == "note" and note_stem(basename(broken.target)) or basename(broken.target),
      folder = folder(broken.target),
      aliases = {},
      tags = {},
      exists = false,
    }
    local key = broken.entry.id .. "\0" .. id
    if not missing_links[key] then
      links[#links + 1] = { source = broken.entry.id, target = id }
      missing_links[key] = true
    end
  end
  if opts.include_tag_nodes then
    for _, entry in ipairs(self._entries) do
      for _, name in ipairs(entry.tags) do
        local id = "tag:" .. name
        add_node { id = id, type = "tag", title = "#" .. name, folder = "", aliases = {}, tags = {}, exists = true }
        links[#links + 1] = { source = entry.id, target = id }
      end
    end
  end
  table.sort(nodes, function(a, b)
    return a.id < b.id
  end)
  table.sort(links, function(a, b)
    if a.source ~= b.source then
      return a.source < b.source
    end
    return a.target < b.target
  end)
  return { nodes = nodes, links = links }
end

return Graph
