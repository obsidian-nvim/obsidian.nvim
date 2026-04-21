--- Vault statistics module. Draft.
---
--- Goal: produce one frozen snapshot (`obsidian.stats.VaultStats`) that every
--- output formatter consumes. Keep collection and presentation separate.
---
--- Reuses:
---   * `obsidian.note.Note`   -- parsing, tags, aliases, frontmatter, body
---   * `obsidian.search`      -- link/backlink discovery
---   * `obsidian.link`        -- unresolved-link detection
---   * `obsidian.fs.dir`      -- gitignore-aware vault walk
---   * `obsidian.util`        -- link parsing
---
--- Do not duplicate these -- call them.

local Note = require "obsidian.note"
local fs = require "obsidian.fs"
local link = require "obsidian.link"
local util = require "obsidian.util"

local M = {}

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
---@field include_backlinks    boolean|?  default false; expensive (per-note rg)
---@field include_unresolved   boolean|?  default true
---@field max_lines            integer|?  passed through to Note.from_file

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

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
---@param note   obsidian.Note
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
  if filter.match and not filter.match(stat, note) then
    return false
  end
  return true
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
  local relpath = note.path:vault_relative_path() or stat_path

  -- File metadata. Single fs_stat.
  local stat_fs = vim.uv.fs_stat(stat_path) or {}

  -- Outgoing links. `Note:links()` -> `search.find_links()` already dedupes.
  -- Classify each match into one of:
  --   internal resolved / internal unresolved / external URI / in-note anchor
  -- Only internal unresolved feeds the unresolved_links list.
  local link_matches = note:links()
  local links_out, links_resolved, links_unresolved = 0, 0, 0
  local links_external, links_anchor = 0, 0
  ---@type obsidian.stats.UnresolvedLink[]
  local unresolved = {}

  for _, m in ipairs(link_matches) do
    local location, _, link_type = util.parse_link(m.link, { strip = false })
    if not location then
      -- Tag/plain -- skip entirely.
    elseif link_type == "HeaderLink" or link_type == "BlockLink" then
      links_anchor = links_anchor + 1
    elseif util.is_uri(location) then
      links_external = links_external + 1
    else
      links_out = links_out + 1
      if opts.include_unresolved ~= false then
        local stripped = util.strip_block_links(util.strip_anchor_links(location))
        local resolved = stripped ~= "" and link.resolve_link_path(stripped) or nil
        if resolved then
          links_resolved = links_resolved + 1
        else
          links_unresolved = links_unresolved + 1
          unresolved[#unresolved + 1] = {
            from = stat_path,
            relpath = relpath,
            line = m.line,
            col = m.start,
            link = m.link,
            location = location,
            reason = "no matching note or file",
          }
        end
      end
    end
  end

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

-- ---------------------------------------------------------------------------
-- Public: collect
-- ---------------------------------------------------------------------------

--- Walk the vault and produce a VaultStats snapshot. Synchronous; for large
--- vaults consider wrapping in `async.run`.
---@param opts obsidian.stats.CollectOpts|?
---@return obsidian.stats.VaultStats
function M.collect(opts)
  opts = opts or {}
  local dir = opts.dir or Obsidian.dir
  local start = vim.uv.hrtime()

  ---@type obsidian.stats.NoteStat[]
  local notes = {}
  ---@type obsidian.stats.UnresolvedLink[]
  local unresolved = {}
  ---@type table<string, string[]>
  local tag_index = {}
  local aggregate = empty_aggregate()

  ---@type obsidian.stats.Topic[]
  local topics = {}
  for _, f in ipairs(opts.topics or {}) do
    topics[#topics + 1] = { name = f.name, filter = f, notes = {}, aggregate = empty_aggregate() }
  end

  for path in fs.dir(dir) do
    local ok, note = pcall(Note.from_file, path, {
      max_lines = opts.max_lines,
      collect_anchor_links = false,
      collect_blocks = true,
    })
    if ok then
      local stat, nu = collect_note(note, opts)
      notes[#notes + 1] = stat
      aggregate_add(aggregate, stat)

      for _, u in ipairs(nu) do
        unresolved[#unresolved + 1] = u
      end

      for _, tag in ipairs(stat.tags) do
        local bucket = tag_index[tag]
        if not bucket then
          bucket = {}
          tag_index[tag] = bucket
        end
        bucket[#bucket + 1] = stat.relpath
      end

      for _, topic in ipairs(topics) do
        if topic_matches(topic.filter, stat, note) then
          topic.notes[#topic.notes + 1] = stat
          aggregate_add(topic.aggregate, stat)
        end
      end
    end
  end

  -- Tags as sorted list.
  ---@type obsidian.stats.TagStat[]
  local tags = {}
  for tag, relpaths in pairs(tag_index) do
    tags[#tags + 1] = { tag = tag, count = #relpaths, notes = relpaths }
  end
  table.sort(tags, function(a, b)
    if a.count == b.count then
      return a.tag < b.tag
    end
    return a.count > b.count
  end)
  aggregate.tags = #tags

  -- Superlatives: O(n) pass per slot.
  ---@param cmp fun(a: obsidian.stats.NoteStat, b: obsidian.stats.NoteStat): boolean
  local function pick(cmp)
    local best
    for _, s in ipairs(notes) do
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
      note_count = #notes,
      generated_at = os.time(),
      scan_ms = scan_ms,
    },
    notes = notes,
    aggregate = aggregate,
    tags = tags,
    unresolved_links = unresolved,
    topics = topics,
    superlatives = superlatives,
  }
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
