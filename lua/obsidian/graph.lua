---Analyze and render a vault graph from the note cache.
---
---A graph is an immutable snapshot of the ready cache. It never scans or reads
---the vault. Create a new graph after the cache changes.
---
---TODO: once attachments are cached, do broken links for attachment links

local cache = require "obsidian.cache"

local MARKDOWN_EXTENSIONS = { md = true, markdown = true, qmd = true, base = true }

---@alias obsidian.graph.NodeType "note"|"tag"|"missing"

---@class obsidian.graph.Node
---@field id string Vault-relative path without its Markdown suffix for note nodes.
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
---@field path string Source note path.
---@field target string Target as written in the cached link.
---@field kind string?
---@field raw string?
---@field line integer?
---@field col integer?

---@class obsidian.graph.Table
---@field nodes obsidian.graph.Node[]
---@field links obsidian.graph.Link[]

---@class obsidian.graph.RenderOpts
---@field include_tag_nodes? boolean Add tag nodes and note-to-tag links. Defaults to false.

---@class obsidian.graph.CachedLink
---@field target any
---@field kind string?
---@field raw string?
---@field line integer?
---@field col integer?

---@class obsidian.graph.Entry
---@field id string
---@field path string
---@field folder string
---@field stem string
---@field title string
---@field aliases string[]
---@field tags string[]
---@field links_out obsidian.graph.CachedLink[]

---@class obsidian.graph.UnresolvedLink
---@field entry obsidian.graph.Entry
---@field link table
---@field target string Normalized, vault-relative target.

---@class obsidian.graph.Analysis
---@field links obsidian.graph.Link[] Resolved note-to-note links.
---@field broken obsidian.graph.UnresolvedLink[]
---@field connected table<string, boolean>

---@class obsidian.Graph
---@field _entries obsidian.graph.Entry[]
---@field _refs table<string, string|false>
---@field _analysis obsidian.graph.Analysis?
---@field _broken_links obsidian.graph.BrokenLink[]?
---@field _orphan_files string[]?
local Graph = {}
Graph.__index = Graph

---@param path string
---@return string
local function strip_markdown_suffix(path)
  local ext = (path:match "%.([^./]+)$" or ""):lower()
  if MARKDOWN_EXTENSIONS[ext] then
    return path:sub(1, #path - #ext - 1)
  end
  return path
end

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

---@param value any
---@return string[]
local function string_list(value)
  local out = {}
  if type(value) ~= "table" then
    return out
  end
  for _, item in ipairs(value) do
    if type(item) == "string" and item ~= "" then
      out[#out + 1] = item
    end
  end
  return out
end

---@param value any
---@return obsidian.graph.CachedLink[]
local function link_list(value)
  local out = {}
  if type(value) ~= "table" then
    return out
  end
  for _, link in ipairs(value) do
    if type(link) == "table" then
      out[#out + 1] = {
        target = link.target,
        kind = link.kind,
        raw = link.raw,
        line = link.line,
        col = link.col,
      }
    end
  end
  return out
end

---@param path string
---@return string
local function normalize_path(path)
  local parts = {}
  for part in path:gsub("\\", "/"):gmatch "[^/]+" do
    if part == ".." then
      if #parts > 0 then
        parts[#parts] = nil
      end
    elseif part ~= "." and part ~= "" then
      parts[#parts + 1] = part
    end
  end
  return table.concat(parts, "/")
end

---@param target any
---@return string?
local function normalize_target(target)
  if type(target) ~= "string" then
    return nil
  end
  target = vim.trim(target)
  if target == "" or target:sub(1, 1) == "#" or target:match "^[%w+.-]+:" then
    return nil
  end

  if target:sub(1, 1) == "<" and target:sub(-1) == ">" then
    target = target:sub(2, -2)
  end
  local ok, decoded = pcall(vim.uri_decode, target)
  if ok then
    target = decoded
  end
  if target:match "^[%w+.-]+:" then
    return nil
  end
  return target:gsub("\\", "/")
end

---@param target string
---@return boolean
local function can_be_note(target)
  local ext = (target:match "%.([^./]+)$" or ""):lower()
  return ext == "" or MARKDOWN_EXTENSIONS[ext] == true
end

---@param refs table<string, string|false>
---@param ref string
---@param id string
local function add_reference(refs, ref, id)
  ref = strip_markdown_suffix(normalize_path(vim.trim(ref))):lower()
  if ref == "" then
    return
  end
  if refs[ref] == nil then
    refs[ref] = id
  elseif refs[ref] ~= id then
    refs[ref] = false
  end
end

---@param target string
---@param entry obsidian.graph.Entry
---@param kind string?
---@return string[]
local function target_candidates(target, entry, kind)
  local absolute = vim.startswith(target, "/")
  local explicitly_relative = vim.startswith(target, "./") or vim.startswith(target, "../")
  local candidates = {}

  if not absolute and (kind == "markdown" or explicitly_relative) then
    candidates[#candidates + 1] = normalize_path(entry.folder .. "/" .. target)
  end
  if not explicitly_relative or absolute then
    candidates[#candidates + 1] = normalize_path(target)
  end

  for i, candidate in ipairs(candidates) do
    candidates[i] = strip_markdown_suffix(candidate)
  end
  return candidates
end

---@param candidates string[]
---@param refs table<string, string|false>
---@return string?
local function resolve_target(candidates, refs)
  for _, candidate in ipairs(candidates) do
    local id = refs[candidate:lower()]
    if id then
      return id
    end
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

---@param a obsidian.graph.Link
---@param b obsidian.graph.Link
---@return boolean
local function link_less(a, b)
  if a.source ~= b.source then
    return a.source < b.source
  end
  return a.target < b.target
end

---@param a obsidian.graph.BrokenLink
---@param b obsidian.graph.BrokenLink
---@return boolean
local function broken_link_less(a, b)
  if a.path ~= b.path then
    return a.path < b.path
  elseif (a.line or 0) ~= (b.line or 0) then
    return (a.line or 0) < (b.line or 0)
  end
  return (a.col or 0) < (b.col or 0)
end

---Create an immutable graph snapshot from the ready note cache.
---@return obsidian.Graph
function Graph.from_cache()
  local self = setmetatable({
    _entries = {},
    _refs = {},
  }, Graph)

  for path, row in pairs(cache.notes.all()) do
    local rel = cache.notes.rel_path(path):gsub("\\", "/")
    local id = strip_markdown_suffix(rel)
    local stem = basename(id)
    local entry = {
      id = id,
      path = path,
      folder = folder(id),
      stem = stem,
      title = note_title(row, stem),
      aliases = string_list(row.aliases),
      tags = string_list(row.tags),
      links_out = link_list(row.links_out),
    }
    self._entries[#self._entries + 1] = entry

    add_reference(self._refs, entry.id, entry.id)
    add_reference(self._refs, entry.stem, entry.id)
    if type(row.id) == "string" then
      add_reference(self._refs, row.id, entry.id)
    end
    for _, alias in ipairs(entry.aliases) do
      add_reference(self._refs, alias, entry.id)
    end
  end

  table.sort(self._entries, function(a, b)
    return a.id < b.id
  end)
  return self
end

---@param self obsidian.Graph
---@return obsidian.graph.Analysis
local function analyze(self)
  if self._analysis then
    return self._analysis
  end

  local analysis = {
    links = {},
    broken = {},
    connected = {},
  }
  local link_ids = {}

  for _, entry in ipairs(self._entries) do
    for _, link in ipairs(entry.links_out) do
      local target = normalize_target(link.target)
      if target then
        local candidates = target_candidates(target, entry, link.kind)
        local resolved = resolve_target(candidates, self._refs)
        if resolved then
          if resolved ~= entry.id then
            local key = entry.id .. "\0" .. resolved
            if not link_ids[key] then
              analysis.links[#analysis.links + 1] = { source = entry.id, target = resolved }
              link_ids[key] = true
            end
            analysis.connected[entry.id] = true
            analysis.connected[resolved] = true
          end
        elseif can_be_note(target) and candidates[1] and candidates[1] ~= "" then
          analysis.broken[#analysis.broken + 1] = {
            entry = entry,
            link = link,
            target = candidates[1],
          }
        end
      end
    end
  end

  self._analysis = analysis
  return analysis
end

---Return missing internal note links.
---
---Attachment links are not checked because attachments are not in the note cache.
---@return obsidian.graph.BrokenLink[]
function Graph:broken_links()
  if self._broken_links then
    return self._broken_links
  end

  local result = {}
  for _, broken in ipairs(analyze(self).broken) do
    local link = broken.link
    result[#result + 1] = {
      source = broken.entry.id,
      path = broken.entry.path,
      target = link.target,
      kind = link.kind,
      raw = link.raw,
      line = link.line,
      col = link.col,
    }
  end
  table.sort(result, broken_link_less)
  self._broken_links = result
  return result
end

-- TODO: tag

---Return absolute paths of notes with no resolved incoming or outgoing note links.
---Tag and broken links do not prevent a note from being an orphan.
---@return string[]
function Graph:orphan_files()
  if self._orphan_files then
    return self._orphan_files
  end

  local analysis = analyze(self)
  local result = {}
  for _, entry in ipairs(self._entries) do
    if not analysis.connected[entry.id] then
      result[#result + 1] = entry.path
    end
  end
  table.sort(result)
  self._orphan_files = result
  return result
end

---Materialize visualization nodes and links from this graph snapshot.
---@param opts obsidian.graph.RenderOpts?
---@return obsidian.graph.Table
function Graph:to_table(opts)
  opts = opts or {}
  local analysis = analyze(self)
  local nodes = {}
  local links = {}
  local node_ids = {}
  local link_ids = {}

  local function add_node(node)
    if not node_ids[node.id] then
      nodes[#nodes + 1] = node
      node_ids[node.id] = true
    end
  end

  local function add_link(source, target)
    if source == target then
      return
    end
    local key = source .. "\0" .. target
    if not link_ids[key] then
      links[#links + 1] = { source = source, target = target }
      link_ids[key] = true
    end
  end

  for _, entry in ipairs(self._entries) do
    add_node {
      id = entry.id,
      type = "note",
      title = entry.title,
      path = entry.path,
      folder = entry.folder,
      aliases = entry.aliases,
      tags = entry.tags,
      exists = true,
    }
  end

  for _, link in ipairs(analysis.links) do
    add_link(link.source, link.target)
  end

  for _, broken in ipairs(analysis.broken) do
    local missing_id = "missing:" .. broken.target
    add_node {
      id = missing_id,
      type = "missing",
      title = basename(broken.target),
      folder = folder(broken.target),
      aliases = {},
      tags = {},
      exists = false,
    }
    add_link(broken.entry.id, missing_id)
  end

  if opts.include_tag_nodes then
    for _, entry in ipairs(self._entries) do
      for _, raw_tag in ipairs(entry.tags) do
        local tag = raw_tag:gsub("^#", "")
        if tag ~= "" then
          local tag_id = "tag:" .. tag
          add_node {
            id = tag_id,
            type = "tag",
            title = "#" .. tag,
            folder = "",
            aliases = {},
            tags = {},
            exists = true,
          }
          add_link(entry.id, tag_id)
        end
      end
    end
  end

  table.sort(nodes, function(a, b)
    return a.id < b.id
  end)
  table.sort(links, link_less)
  return { nodes = nodes, links = links }
end

return Graph
