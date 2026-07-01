--- Vault statistics module. Draft.
---
--- Goal: produce one frozen snapshot (`obsidian.stats.VaultStats`) that every
--- output formatter consumes. Keep collection and presentation separate.
---
--- Reuses cache rows when available, and exposes an async collector so callers
--- don't have to block the UI for large vaults.

local Note = require "obsidian.note"
local cache = require "obsidian.cache"
local fs = require "obsidian.fs"
local link = require "obsidian.link"
local util = require "obsidian.util"

local M = {}

local DEFAULT_MAX_LINES = 500
local DEFAULT_BATCH_SIZE = 64

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

---@class obsidian.stats.NoteStat
--- One row per note. All fields derivable from a single `Note.from_file` pass
--- plus one link scan. Keep numeric fields numbers (not strings) so that JSON
--- / CSV emitters can format them as they please.
---@field id         string
---@field title      string|?
---@field path       string          absolute
---@field relpath    string          vault-relative
---@field aliases    string[]
---@field tags       string[]
---@field words      integer
---@field chars      integer
---@field lines      integer
---@field bytes      integer
---@field headers    integer
---@field blocks     integer
---@field links_out         integer   internal note links only (excl. URIs, anchors)
---@field links_resolved    integer
---@field links_unresolved  integer
---@field links_external    integer   http(s)/mailto/etc URIs
---@field links_anchor      integer   in-note `#heading` / `#^block` links
---@field backlinks        integer
---@field has_frontmatter  boolean
---@field mtime            integer  epoch seconds
---@field ctime            integer  epoch seconds

---@class obsidian.stats.UnresolvedLink
---@field from     string   absolute path of source note
---@field relpath  string   vault-relative path of source
---@field line     integer  1-indexed
---@field col      integer  0-indexed (`start` from LinkMatch)
---@field link     string   raw link text as it appears in the file
---@field location string|? parsed location (post parse_link)
---@field reason   string   why it failed to resolve

---@class obsidian.stats.TagStat
---@field tag    string
---@field count  integer       occurrences across vault (one per tagged note)
---@field notes  string[]      relpaths of notes carrying the tag

---@class obsidian.stats.Aggregate
---@field notes             integer
---@field words             integer
---@field chars             integer
---@field lines             integer
---@field bytes             integer
---@field links_out         integer
---@field links_resolved    integer
---@field links_unresolved  integer
---@field links_external    integer
---@field links_anchor      integer
---@field backlinks         integer
---@field with_frontmatter    integer
---@field without_frontmatter integer
---@field orphans           integer  notes with 0 backlinks
---@field leafs             integer  notes with 0 outgoing links
---@field tags              integer  unique tag count

---@class obsidian.stats.Superlatives
---@field most_words     obsidian.stats.NoteStat|?
---@field fewest_words   obsidian.stats.NoteStat|?
---@field most_links     obsidian.stats.NoteStat|?
---@field most_backlinks obsidian.stats.NoteStat|?
---@field largest        obsidian.stats.NoteStat|?

--- A filter groups notes into a named bucket.
--- `match(note_stat, note)` is called during collection. Return truthy to
--- include. Can be expressed three equivalent ways:
---
---   { name = "Projects", path_prefix = "projects/" }
---   { name = "Book",     tag = "book" }
---   { name = "Big",      match = function(s) return s.words > 2000 end }
---
--- Composition: pass multiple filters in `opts.topics`; a note may appear in
--- more than one topic.
---@class obsidian.stats.TopicFilter
---@field name         string
---@field tag          string|?           match if note has this tag
---@field path_prefix  string|?           match if relpath starts with this
---@field path_pattern string|?           Lua pattern against relpath
---@field match        (fun(stat: obsidian.stats.NoteStat, note: obsidian.Note): boolean)|?

---@class obsidian.stats.Topic
---@field name       string
---@field filter     obsidian.stats.TopicFilter
---@field notes      obsidian.stats.NoteStat[]
---@field aggregate  obsidian.stats.Aggregate

---@class obsidian.stats.VaultStats
---@field vault {
---   dir: string,
---   note_count: integer,
---   generated_at: integer,
---   scan_ms: integer,
--- }
---@field notes             obsidian.stats.NoteStat[]
---@field aggregate         obsidian.stats.Aggregate
---@field tags              obsidian.stats.TagStat[]
---@field unresolved_links  obsidian.stats.UnresolvedLink[]
---@field topics            obsidian.stats.Topic[]
---@field superlatives      obsidian.stats.Superlatives

---@class obsidian.stats.CollectOpts
---@field dir                  string|obsidian.Path|?   defaults to `Obsidian.dir`
---@field topics               obsidian.stats.TopicFilter[]|?
---@field include_backlinks    boolean|?  default false; expensive without cache
---@field include_unresolved   boolean|?  default true
---@field max_lines            integer|?  passed through to Note.from_file
---@field use_cache            boolean|?  default true
---@field batch_size           integer|?  async notes processed per scheduler tick
---@field timeout              integer|?  sync `collect()` timeout in ms

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

---@return obsidian.stats.Aggregate
local function empty_aggregate()
  return {
    notes = 0,
    words = 0,
    chars = 0,
    lines = 0,
    bytes = 0,
    links_out = 0,
    links_resolved = 0,
    links_unresolved = 0,
    links_external = 0,
    links_anchor = 0,
    backlinks = 0,
    with_frontmatter = 0,
    without_frontmatter = 0,
    orphans = 0,
    leafs = 0,
    tags = 0,
  }
end

---@param agg obsidian.stats.Aggregate
---@param s   obsidian.stats.NoteStat
local function aggregate_add(agg, s)
  agg.notes = agg.notes + 1
  agg.words = agg.words + s.words
  agg.chars = agg.chars + s.chars
  agg.lines = agg.lines + s.lines
  agg.bytes = agg.bytes + s.bytes
  agg.links_out = agg.links_out + s.links_out
  agg.links_resolved = agg.links_resolved + s.links_resolved
  agg.links_unresolved = agg.links_unresolved + s.links_unresolved
  agg.links_external = agg.links_external + s.links_external
  agg.links_anchor = agg.links_anchor + s.links_anchor
  agg.backlinks = agg.backlinks + s.backlinks
  if s.has_frontmatter then
    agg.with_frontmatter = agg.with_frontmatter + 1
  else
    agg.without_frontmatter = agg.without_frontmatter + 1
  end
  if s.backlinks == 0 then
    agg.orphans = agg.orphans + 1
  end
  if s.links_out == 0 then
    agg.leafs = agg.leafs + 1
  end
end

---@param filter obsidian.stats.TopicFilter
---@param stat   obsidian.stats.NoteStat
---@param note   obsidian.Note|nil
local function topic_matches(filter, stat, note)
  if filter.tag and not vim.list_contains(stat.tags, filter.tag) then
    return false
  end
  if filter.path_prefix and not vim.startswith(stat.relpath, filter.path_prefix) then
    return false
  end
  if filter.path_pattern and not stat.relpath:match(filter.path_pattern) then
    return false
  end
  if filter.match and (not note or not filter.match(stat, note)) then
    return false
  end
  return true
end

---@param lines string[]
---@return integer words, integer chars, integer headers
local function scan_body(lines)
  local words, chars, headers = 0, 0, 0
  for _, line in ipairs(lines) do
    chars = chars + #line
    if line:match "^%s*#+%s" then
      headers = headers + 1
    end
    for _ in line:gmatch "%S+" do
      words = words + 1
    end
  end
  return words, chars, headers
end

---@param abs_path string
---@param max_lines integer|?
---@return table?
local function scan_file(abs_path, max_lines)
  local fh = io.open(abs_path, "r")
  if not fh then
    return nil
  end

  max_lines = max_lines or DEFAULT_MAX_LINES
  local lines = {}
  for line in fh:lines() do
    lines[#lines + 1] = util.rstrip_whitespace(line)
    if #lines > max_lines then
      break
    end
  end
  fh:close()

  local has_frontmatter = lines[1] ~= nil and Note._is_frontmatter_boundary(lines[1])
  local frontmatter_end_line
  if has_frontmatter then
    for i = 2, #lines do
      if Note._is_frontmatter_boundary(lines[i]) then
        frontmatter_end_line = i
        break
      end
    end
  end

  local body = {}
  local first_body_line = has_frontmatter and frontmatter_end_line and (frontmatter_end_line + 1) or 1
  local blocks = {}
  for i = first_body_line, #lines do
    body[#body + 1] = lines[i]
    local block = util.parse_block(lines[i])
    if block then
      blocks[block] = true
    end
  end

  local words, chars, headers = scan_body(body)
  return {
    has_frontmatter = has_frontmatter,
    words = words,
    chars = chars,
    lines = #body,
    headers = headers,
    blocks = vim.tbl_count(blocks),
  }
end

---@param location string
---@return string
local function strip_link_location(location)
  local stripped = util.strip_block_links(util.strip_anchor_links(location))
  return stripped
end

---@param path string
---@return string
local function drop_ext(path)
  return (path:gsub("%.[^./]+$", ""))
end

---@param idx table<string, string>
---@param key string|nil
---@param path string
local function add_index_key(idx, key, path)
  if key and key ~= "" then
    key = key:gsub("^/", ""):gsub("^%./", "")
    if not idx[key] then
      idx[key] = path
    end
    local lower = key:lower()
    if not idx[lower] then
      idx[lower] = path
    end
  end
end

---@param rows table<string, table>
---@param dir string|obsidian.Path
---@return table<string, integer> backlinks_by_path
---@return fun(location:string): string?
local function build_cache_resolver(rows, dir)
  local by_key = {}
  local by_abs = {}
  local root = vim.fs.normalize(tostring(dir)):gsub("/+$", "")

  for path, row in pairs(rows) do
    path = vim.fs.normalize(path)
    by_abs[path] = path
    local rel = path
    if vim.startswith(path, root .. "/") then
      rel = path:sub(#root + 2)
    end
    add_index_key(by_key, rel, path)
    add_index_key(by_key, drop_ext(rel), path)
    add_index_key(by_key, vim.fn.fnamemodify(path, ":t"), path)
    add_index_key(by_key, vim.fn.fnamemodify(path, ":t:r"), path)
    for _, alias in ipairs(row.aliases or {}) do
      add_index_key(by_key, alias, path)
    end
  end

  ---@param location string
  ---@return string?
  local function resolve(location)
    location = strip_link_location(location)
    if location == "" or util.is_uri(location) then
      return nil
    end

    local normalized = vim.fs.normalize(vim.uri_decode(location))
    if by_abs[normalized] then
      return by_abs[normalized]
    end

    normalized = normalized:gsub("^/", ""):gsub("^%./", "")
    return by_key[normalized]
      or by_key[normalized:lower()]
      or by_key[drop_ext(normalized)]
      or by_key[drop_ext(normalized):lower()]
  end

  local backlinks_by_path = {}
  for path in pairs(rows) do
    backlinks_by_path[vim.fs.normalize(path)] = 0
  end

  for from_path, row in pairs(rows) do
    local seen = {}
    for _, l in ipairs(row.links_out or {}) do
      local target = l.target or ""
      if target ~= "" and not util.is_uri(target) then
        local resolved = resolve(target)
        if resolved and resolved ~= vim.fs.normalize(from_path) and not seen[resolved] then
          backlinks_by_path[resolved] = (backlinks_by_path[resolved] or 0) + 1
          seen[resolved] = true
        end
      end
    end
  end

  return backlinks_by_path, resolve
end

---@param m obsidian.LinkMatch
---@return table?
local function link_match_to_cache_shape(m)
  local location, _, link_type = util.parse_link(m.link)
  if not location then
    return nil
  end
  local target, block = util.strip_block_links(location)
  target = util.strip_anchor_links(target)
  local anchor = location:match "#([^#]+)$"
  return {
    raw = m.link,
    target = target,
    anchor = anchor,
    block = block and block:gsub("^#%^", "") or nil,
    kind = link_type,
    line = m.line,
    col = m.start + 1,
  }
end

---@param l table
---@return string
local function raw_link(l)
  if l.embed and type(l.raw) == "string" and vim.startswith(l.raw, "!") then
    return l.raw:sub(2)
  end
  return l.raw or l.link or l.target or ""
end

---@param l table
---@return string
local function link_location(l)
  local location = l.target or ""
  if l.block then
    location = location .. "#^" .. tostring(l.block):gsub("^%^", "")
  elseif l.anchor then
    location = location .. "#" .. tostring(l.anchor):gsub("^#", "")
  end
  return location
end

---@param links table[]
---@param stat_path string
---@param relpath string
---@param opts obsidian.stats.CollectOpts
---@param resolve fun(location:string): string?|nil
---@return integer, integer, integer, integer, integer, obsidian.stats.UnresolvedLink[]
local function classify_links(links, stat_path, relpath, opts, resolve)
  local links_out, links_resolved, links_unresolved = 0, 0, 0
  local links_external, links_anchor = 0, 0
  local unresolved = {}
  local found = {}

  for _, l in ipairs(links) do
    local raw = raw_link(l)
    if raw ~= "" and not found[raw] then
      found[raw] = true
      local location = link_location(l)
      local target = l.target or ""
      if target == "" and (l.anchor or l.block) then
        links_anchor = links_anchor + 1
      elseif util.is_uri(target) then
        links_external = links_external + 1
      elseif target ~= "" then
        links_out = links_out + 1
        if opts.include_unresolved ~= false then
          local resolved
          if resolve then
            resolved = resolve(location)
          else
            resolved = link.resolve_link_path(location)
          end
          if resolved then
            links_resolved = links_resolved + 1
          else
            links_unresolved = links_unresolved + 1
            unresolved[#unresolved + 1] = {
              from = stat_path,
              relpath = relpath,
              line = l.line or 0,
              col = math.max((l.col or 1) - 1 + (l.embed and 1 or 0), 0),
              link = raw,
              location = location,
              reason = "no matching note or file",
            }
          end
        end
      end
    end
  end

  return links_out, links_resolved, links_unresolved, links_external, links_anchor, unresolved
end

---@param topics obsidian.stats.TopicFilter[]|nil
---@return boolean
local function has_custom_topic_match(topics)
  for _, topic in ipairs(topics or {}) do
    if topic.match then
      return true
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Per-note collection
-- ---------------------------------------------------------------------------

---@param note   obsidian.Note
---@param opts   obsidian.stats.CollectOpts
---@return obsidian.stats.NoteStat
---@return obsidian.stats.UnresolvedLink[] unresolved links found in this note
local function collect_note(note, opts)
  local body = note:body_lines()
  local words, chars, headers = scan_body(body)
  local stat_path = tostring(note.path)
  local root = vim.fs.normalize(tostring(opts.dir or Obsidian.dir)):gsub("/+$", "")
  local relpath = vim.startswith(stat_path, root .. "/") and stat_path:sub(#root + 2) or stat_path
  local stat_fs = vim.uv.fs_stat(stat_path) or {}
  local parsed_links = {}

  for _, m in ipairs(note:links()) do
    local l = link_match_to_cache_shape(m)
    if l then
      parsed_links[#parsed_links + 1] = l
    end
  end

  local links_out, links_resolved, links_unresolved, links_external, links_anchor, unresolved =
    classify_links(parsed_links, stat_path, relpath, opts, nil)

  local backlinks = 0
  if opts.include_backlinks then
    backlinks = #note:backlinks {}
  end

  ---@type obsidian.stats.NoteStat
  local stat = {
    id = tostring(note.id),
    title = note.title,
    path = stat_path,
    relpath = relpath,
    aliases = vim.deepcopy(note.aliases),
    tags = vim.deepcopy(note.tags),
    words = words,
    chars = chars,
    lines = #body,
    bytes = stat_fs.size or 0,
    headers = headers,
    blocks = vim.tbl_count(note.blocks or {}),
    links_out = links_out,
    links_resolved = links_resolved,
    links_unresolved = links_unresolved,
    links_external = links_external,
    links_anchor = links_anchor,
    backlinks = backlinks,
    has_frontmatter = note.has_frontmatter == true,
    mtime = stat_fs.mtime and stat_fs.mtime.sec or 0,
    ctime = stat_fs.ctime and stat_fs.ctime.sec or 0,
  }

  return stat, unresolved
end

---@param path string
---@param row table
---@param opts obsidian.stats.CollectOpts
---@param dir string|obsidian.Path
---@param backlinks_by_path table<string, integer>
---@param resolve fun(location:string): string?
---@return obsidian.stats.NoteStat?
---@return obsidian.stats.UnresolvedLink[]
local function collect_cached_note(path, row, opts, dir, backlinks_by_path, resolve)
  path = vim.fs.normalize(path)
  local file_scan = scan_file(path, opts.max_lines)
  if not file_scan then
    return nil, {}
  end

  local stat_fs = vim.uv.fs_stat(path) or {}
  local root = vim.fs.normalize(tostring(dir)):gsub("/+$", "")
  local relpath = vim.startswith(path, root .. "/") and path:sub(#root + 2) or path
  local properties = row.properties or {}
  local links_out, links_resolved, links_unresolved, links_external, links_anchor, unresolved =
    classify_links(row.links_out or {}, path, relpath, opts, resolve)

  local id = type(properties.id) == "string" and properties.id or vim.fn.fnamemodify(path, ":t:r")

  ---@type obsidian.stats.NoteStat
  local stat = {
    id = id,
    title = type(properties.title) == "string" and properties.title or nil,
    path = path,
    relpath = relpath,
    aliases = vim.deepcopy(row.aliases or {}),
    tags = vim.deepcopy(row.tags or {}),
    words = file_scan.words,
    chars = file_scan.chars,
    lines = file_scan.lines,
    bytes = row.size or stat_fs.size or 0,
    headers = file_scan.headers,
    blocks = file_scan.blocks,
    links_out = links_out,
    links_resolved = links_resolved,
    links_unresolved = links_unresolved,
    links_external = links_external,
    links_anchor = links_anchor,
    backlinks = opts.include_backlinks and (backlinks_by_path[path] or 0) or 0,
    has_frontmatter = file_scan.has_frontmatter,
    mtime = row.mtime or (stat_fs.mtime and stat_fs.mtime.sec) or 0,
    ctime = stat_fs.ctime and stat_fs.ctime.sec or 0,
  }

  return stat, unresolved
end

-- ---------------------------------------------------------------------------
-- Collection state/finalization
-- ---------------------------------------------------------------------------

---@param opts obsidian.stats.CollectOpts
---@return table
local function new_collect_state(opts)
  local topics = {}
  for _, f in ipairs(opts.topics or {}) do
    topics[#topics + 1] = { name = f.name, filter = f, notes = {}, aggregate = empty_aggregate() }
  end

  return {
    notes = {},
    unresolved = {},
    tag_index = {},
    aggregate = empty_aggregate(),
    topics = topics,
  }
end

---@param state table
---@param stat obsidian.stats.NoteStat
---@param note obsidian.Note|nil
local function add_note_stat(state, stat, note)
  state.notes[#state.notes + 1] = stat
  aggregate_add(state.aggregate, stat)

  for _, tag in ipairs(stat.tags) do
    local bucket = state.tag_index[tag]
    if not bucket then
      bucket = {}
      state.tag_index[tag] = bucket
    end
    bucket[#bucket + 1] = stat.relpath
  end

  for _, topic in ipairs(state.topics) do
    if topic_matches(topic.filter, stat, note) then
      topic.notes[#topic.notes + 1] = stat
      aggregate_add(topic.aggregate, stat)
    end
  end
end

---@param state table
---@param unresolved obsidian.stats.UnresolvedLink[]
local function add_unresolved(state, unresolved)
  for _, u in ipairs(unresolved) do
    state.unresolved[#state.unresolved + 1] = u
  end
end

---@param state table
---@param dir string|obsidian.Path
---@param start integer
---@return obsidian.stats.VaultStats
local function finish_collect(state, dir, start)
  ---@type obsidian.stats.TagStat[]
  local tags = {}
  for tag, relpaths in pairs(state.tag_index) do
    tags[#tags + 1] = { tag = tag, count = #relpaths, notes = relpaths }
  end
  table.sort(tags, function(a, b)
    if a.count == b.count then
      return a.tag < b.tag
    end
    return a.count > b.count
  end)
  state.aggregate.tags = #tags

  ---@param cmp fun(a: obsidian.stats.NoteStat, b: obsidian.stats.NoteStat): boolean
  local function pick(cmp)
    local best
    for _, s in ipairs(state.notes) do
      if not best or cmp(s, best) then
        best = s
      end
    end
    return best
  end

  local superlatives = {
    most_words = pick(function(a, b)
      return a.words > b.words
    end),
    fewest_words = pick(function(a, b)
      return a.words < b.words
    end),
    most_links = pick(function(a, b)
      return a.links_out > b.links_out
    end),
    most_backlinks = pick(function(a, b)
      return a.backlinks > b.backlinks
    end),
    largest = pick(function(a, b)
      return a.bytes > b.bytes
    end),
  }

  local scan_ms = math.floor((vim.uv.hrtime() - start) / 1e6)

  return {
    vault = {
      dir = tostring(dir),
      note_count = #state.notes,
      generated_at = os.time(),
      scan_ms = scan_ms,
    },
    notes = state.notes,
    aggregate = state.aggregate,
    tags = tags,
    unresolved_links = state.unresolved,
    topics = state.topics,
    superlatives = superlatives,
  }
end

---@param opts obsidian.stats.CollectOpts
---@param dir string|obsidian.Path
---@return boolean
local function should_use_cache(opts, dir)
  if opts.use_cache == false or not cache.is_enabled() or has_custom_topic_match(opts.topics) then
    return false
  end
  if opts.dir and Obsidian and Obsidian.dir then
    return vim.fs.normalize(tostring(dir)) == vim.fs.normalize(tostring(Obsidian.dir))
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Public: collect
-- ---------------------------------------------------------------------------

---@param opts obsidian.stats.CollectOpts|?
---@param callback fun(stats: obsidian.stats.VaultStats?, err: string?)
---@return table handle cancellable via `handle:kill()`
function M.collect_async(opts, callback)
  opts = opts or {}
  local dir = opts.dir or Obsidian.dir
  local start = vim.uv.hrtime()
  local batch_size = opts.batch_size or DEFAULT_BATCH_SIZE
  local cancelled = false

  local handle = {}
  function handle:kill()
    cancelled = true
  end

  local function fail(err)
    if not cancelled then
      callback(nil, tostring(err))
    end
  end

  local function done(stats)
    if not cancelled then
      callback(stats, nil)
    end
  end

  local function collect_from_files_async()
    local ok, paths_or_err = pcall(function()
      local paths = {}
      for path in fs.dir(dir) do
        paths[#paths + 1] = path
      end
      return paths
    end)
    if not ok then
      return fail(paths_or_err)
    end

    local paths = paths_or_err
    local state = new_collect_state(opts)
    local i = 1

    local function step()
      if cancelled then
        return
      end
      local stop = math.min(i + batch_size - 1, #paths)
      while i <= stop do
        local ok_note, note = pcall(Note.from_file, paths[i], {
          max_lines = opts.max_lines,
          collect_anchor_links = false,
          collect_blocks = true,
        })
        if ok_note then
          local ok_stat, stat, nu = pcall(collect_note, note, opts)
          if not ok_stat then
            return fail(stat)
          end
          add_note_stat(state, stat, note)
          add_unresolved(state, nu)
        end
        i = i + 1
      end

      if i <= #paths then
        vim.schedule(step)
      else
        done(finish_collect(state, dir, start))
      end
    end

    vim.schedule(step)
  end

  local function collect_from_cache_async()
    local ok_rows, rows_or_err = pcall(function()
      return cache.notes.all()
    end)
    if not ok_rows then
      return fail(rows_or_err)
    end

    local rows = rows_or_err
    local backlinks_by_path, resolve = build_cache_resolver(rows, dir)
    local items = {}
    for path, row in pairs(rows) do
      items[#items + 1] = { path = path, row = row }
    end
    table.sort(items, function(a, b)
      return a.path < b.path
    end)

    local state = new_collect_state(opts)
    local i = 1

    local function step()
      if cancelled then
        return
      end
      local stop = math.min(i + batch_size - 1, #items)
      while i <= stop do
        local item = items[i]
        local ok_stat, stat, nu = pcall(collect_cached_note, item.path, item.row, opts, dir, backlinks_by_path, resolve)
        if not ok_stat then
          return fail(stat)
        end
        if stat then
          add_note_stat(state, stat, nil)
          add_unresolved(state, nu)
        end
        i = i + 1
      end

      if i <= #items then
        vim.schedule(step)
      else
        done(finish_collect(state, dir, start))
      end
    end

    vim.schedule(step)
  end

  if should_use_cache(opts, dir) then
    cache.when_ready(collect_from_cache_async)
  else
    collect_from_files_async()
  end

  return handle
end

-- ---------------------------------------------------------------------------
-- Public: format
-- ---------------------------------------------------------------------------

--- Render a VaultStats snapshot to a string.
---@param stats obsidian.stats.VaultStats
---@param format "markdown"|"json"|"csv"|string
---@param opts   table|?   forwarded to the formatter
---@return string
function M.format(stats, format, opts)
  return require("obsidian.stats.format").render(stats, format, opts)
end

return M
