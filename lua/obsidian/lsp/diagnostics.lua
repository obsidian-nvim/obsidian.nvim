local Note = require "obsidian.note"
local Range = require "obsidian.range"
local api = require "obsidian.api"
local cache = require "obsidian.cache"
local parse_refs = require "obsidian.parse.refs"
local util = require "obsidian.util"

local M = {}

local DEBOUNCE_MS = 500

---@class obsidian.lsp.PendingDiagnostics
---@field timer uv.uv_timer_t
---@field params table
---@field dispatchers table
---@field revision integer

---@type table<string, obsidian.lsp.PendingDiagnostics>
local pending = {}
---@type table<string, integer>
local revisions = {}
---@type table<string, table>
local document_dispatchers = {}

---@param params table?
---@return string?
local function params_uri(params)
  return params and params.textDocument and params.textDocument.uri or nil
end

---@param uri string
---@return string
local function buffer_source(uri)
  local bufnr = vim.uri_to_bufnr(uri)
  if vim.api.nvim_buf_is_loaded(bufnr) then
    return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  end
  return ""
end

---@param params table
---@return string
local function params_source(params)
  if params.textDocument and type(params.textDocument.text) == "string" then
    return params.textDocument.text
  end
  local changes = params.contentChanges
  if changes and changes[#changes] and type(changes[#changes].text) == "string" then
    return changes[#changes].text
  end
  return buffer_source(assert(params_uri(params), "missing text document URI"))
end

---@class obsidian.lsp.DiagnosticLink
---@field ref obsidian.parse.Ref
---@field count integer?
---@field description string

---@class obsidian.lsp.CachedDestination
---@field path string?
---@field row table?
---@field note obsidian.Note?

---@class obsidian.lsp.DiagnosticCacheIndex
---@field identifiers table<string, obsidian.lsp.CachedDestination[]>
---@field paths table<string, obsidian.lsp.CachedDestination>

---@class obsidian.lsp.DiagnosticContext
---@field source string
---@field lines string[]
---@field note obsidian.Note
---@field diagnostics lsp.Diagnostic[]
---@field links obsidian.lsp.DiagnosticLink[]?
---@field resolved table<string, obsidian.lsp.CachedDestination[]|false>
---@field cache_index obsidian.lsp.DiagnosticCacheIndex?

---@param ref obsidian.parse.Ref
---@return lsp.Diagnostic
local function link_diagnostic(ref)
  return {
    range = Range.to_lsp(ref.range),
    severity = vim.diagnostic.severity.HINT,
    source = "obsidian-ls",
    message = "",
  }
end

---@param lines string[]
---@return obsidian.parse.Ref[]
local function document_refs(lines)
  local refs = {}
  local in_frontmatter = false
  local fence
  local function is_frontmatter_boundary(line)
    return line:match "^%-%-%-+$" ~= nil
  end

  for row, line in ipairs(lines) do
    if row == 1 and is_frontmatter_boundary(line) then
      in_frontmatter = true
    elseif in_frontmatter then
      if is_frontmatter_boundary(line) then
        in_frontmatter = false
      end
    else
      local marker = line:match "^%s*(```+)" or line:match "^%s*(~~~+)"
      if marker then
        if fence == nil then
          fence = marker:sub(1, 1)
        elseif fence == marker:sub(1, 1) then
          fence = nil
        end
      elseif fence == nil then
        vim.list_extend(refs, parse_refs.extract(line, { row = row - 1 }))
      end
    end
  end

  return refs
end

---@param target string
---@param kind obsidian.parse.RefKind
---@return boolean
local function ignored_target(target, kind)
  if util.is_uri(target) or api.is_attachment_path(target) then
    return true
  elseif kind ~= "markdown" then
    return false
  end

  local extension = vim.fs.basename(target):match "%.([^./]+)$"
  return extension ~= nil and not vim.list_contains({ "md", "qmd", "base" }, extension:lower())
end

---@param destination obsidian.lsp.CachedDestination
---@param ref obsidian.parse.Ref
---@return integer
local function destination_count(destination, ref)
  if ref.anchor then
    local anchor = util.standardize_anchor("#" .. ref.anchor)
    if destination.note then
      local count = 0
      for _, section in ipairs(destination.note.sections or {}) do
        if section.anchor == anchor then
          count = count + 1
        end
      end
      if count > 0 then
        return count
      end
      return destination.note.anchor_links and destination.note.anchor_links[anchor] and 1 or 0
    end
    return destination.row and destination.row.anchors and destination.row.anchors[anchor] or 0
  elseif ref.block then
    local block = util.standardize_block(ref.block)
    if destination.note then
      return destination.note.blocks and destination.note.blocks[block] and 1 or 0
    end
    return destination.row and destination.row.blocks and destination.row.blocks[block] and 1 or 0
  end
  return 1
end

---@param ref obsidian.parse.Ref
---@param target string
---@return string
local function ref_description(ref, target)
  local document = target ~= "" and (" in document '%s'"):format(target) or ""
  if ref.anchor then
    return ("heading '%s'%s"):format(ref.anchor, document)
  elseif ref.block then
    return ("block '^%s'%s"):format(ref.block:gsub("%^", ""), document)
  end
  return ("document '%s'"):format(target)
end

local MARKDOWN_EXTENSIONS = { "md", "markdown", "qmd", "base" }

---@param value string
---@return string
local function normalize_identifier(value)
  value = value:gsub("\\", "/"):gsub("^%./", "")
  return value:lower()
end

---@param context obsidian.lsp.DiagnosticContext
---@return obsidian.lsp.DiagnosticCacheIndex
local function build_cache_index(context)
  if context.cache_index then
    return context.cache_index
  end

  local index = { identifiers = {}, paths = {} }
  local current_path = vim.fs.normalize(tostring(context.note.path))
  local current_indexed = false

  local function add(path, row)
    path = vim.fs.normalize(path)
    local destination
    if path == current_path then
      destination = { note = context.note }
      current_indexed = true
    else
      destination = { path = path, row = row }
    end
    index.paths[path:lower()] = destination

    local rel_path = cache.notes.rel_path(path)
    local basename = vim.fs.basename(path)
    local stem = basename:gsub("%.[^./]+$", "")
    local rel_stem = rel_path:gsub("%.[^./]+$", "")
    local identifiers = { basename, stem, rel_path, rel_stem, row.id }
    vim.list_extend(identifiers, row.aliases or {})
    if destination.note then
      vim.list_extend(identifiers, destination.note:reference_ids())
    end
    for _, identifier in ipairs(identifiers) do
      if identifier then
        identifier = normalize_identifier(tostring(identifier))
        index.identifiers[identifier] = index.identifiers[identifier] or {}
        index.identifiers[identifier][#index.identifiers[identifier] + 1] = destination
      end
    end
  end

  for path, row in pairs(cache.notes.all()) do
    add(path, row)
  end
  if not current_indexed then
    add(current_path, {})
  end

  context.cache_index = index
  return index
end

---@param context obsidian.lsp.DiagnosticContext
---@param target string
---@return obsidian.lsp.CachedDestination[]?
local function resolve_from_cache(context, target)
  local cached = context.resolved[target]
  if cached ~= nil then
    return cached ~= false and cached or nil
  elseif not cache.is_ready() then
    context.resolved[target] = false
    return nil
  end

  local index = build_cache_index(context)
  local destinations = {}
  local found = {}
  local function add(destination)
    local key = destination.path or tostring(context.note.path)
    if not found[key] then
      found[key] = true
      destinations[#destinations + 1] = destination
    end
  end
  for _, destination in ipairs(index.identifiers[normalize_identifier(target)] or {}) do
    add(destination)
  end

  local function add_target_path(candidate)
    local destination = index.paths[vim.fs.normalize(candidate):lower()]
    if destination then
      add(destination)
    end
  end
  local function add_with_extensions(candidate)
    add_target_path(candidate)
    if not candidate:match "%.[^./]+$" then
      for _, extension in ipairs(MARKDOWN_EXTENSIONS) do
        add_target_path(candidate .. "." .. extension)
      end
    end
  end

  if vim.startswith(target, "/") then
    add_with_extensions(target)
  else
    local current_path = tostring(context.note.path)
    add_with_extensions(vim.fs.joinpath(vim.fs.dirname(current_path), target))
    add_with_extensions(vim.fs.joinpath(tostring(Obsidian.dir), target))
  end

  context.resolved[target] = destinations
  return destinations
end

---@param context obsidian.lsp.DiagnosticContext
---@return obsidian.lsp.DiagnosticLink[]
local function resolve_links(context)
  if context.links then
    return context.links
  end

  context.links = {}
  for _, ref in ipairs(document_refs(context.lines)) do
    if ref.kind ~= "footnote" then
      local target = vim.uri_decode(ref.target)
      if (target ~= "" or ref.anchor or ref.block) and not ignored_target(target, ref.kind) then
        ---@type obsidian.lsp.CachedDestination[]?
        local destinations
        if target == "" then
          destinations = { { note = context.note } }
        else
          destinations = resolve_from_cache(context, target)
        end

        local count
        if destinations then
          count = 0
          for _, destination in ipairs(destinations) do
            count = count + destination_count(destination, ref)
          end
        end
        context.links[#context.links + 1] = {
          ref = ref,
          count = count,
          description = ref_description(ref, target),
        }
      end
    end
  end

  return context.links
end

---@param context obsidian.lsp.DiagnosticContext
local function broken_link_handler(context)
  for _, link in ipairs(resolve_links(context)) do
    if link.count == 0 then
      local diagnostic = link_diagnostic(link.ref)
      diagnostic.code = "broken-link"
      diagnostic.message = "Link to non-existent " .. link.description
      context.diagnostics[#context.diagnostics + 1] = diagnostic
    end
  end
end

---@param context obsidian.lsp.DiagnosticContext
local function ambiguous_link_handler(context)
  for _, link in ipairs(resolve_links(context)) do
    if link.count and link.count > 1 then
      local diagnostic = link_diagnostic(link.ref)
      diagnostic.code = "ambiguous-link"
      diagnostic.message = "Ambiguous link to " .. link.description
      context.diagnostics[#context.diagnostics + 1] = diagnostic
    end
  end
end

---@param context obsidian.lsp.DiagnosticContext
local function non_breaking_whitespace_handler(context)
  for row, line in ipairs(context.lines) do
    local hashes = line:match "^(#+)\194\160"
    if hashes and #hashes <= 7 then
      context.diagnostics[#context.diagnostics + 1] = {
        range = {
          start = { line = row - 1, character = #hashes },
          ["end"] = { line = row - 1, character = #hashes + 1 },
        },
        severity = vim.diagnostic.severity.WARN,
        code = "non-breaking-whitespace",
        source = "obsidian-ls",
        message = "Non-breaking whitespace used instead of regular whitespace. This line won't be interpreted as a heading",
      }
    end
  end
end

---@type fun(context: obsidian.lsp.DiagnosticContext)[]
local handlers = {
  broken_link_handler,
  ambiguous_link_handler,
  non_breaking_whitespace_handler,
}

-- TODO: Diagnose duplicate block IDs, unresolved/duplicate footnotes and link
-- definitions, malformed links, unclosed code fences, and invalid frontmatter.

---@param source string
---@param uri string
---@return lsp.Diagnostic[]
local function analyze(source, uri)
  local lines = vim.split(source, "\n", { plain = true })
  local context = {
    source = source,
    lines = lines,
    note = Note.from_lines(lines, vim.uri_to_fname(uri), {
      collect_anchor_links = true,
      collect_blocks = true,
      collect_sections = true,
    }),
    diagnostics = {},
    resolved = {},
  }

  for _, handler in ipairs(handlers) do
    handler(context)
  end

  table.sort(context.diagnostics, function(left, right)
    if left.range.start.line == right.range.start.line then
      return left.range.start.character < right.range.start.character
    end
    return left.range.start.line < right.range.start.line
  end)
  return context.diagnostics
end

---@param uri string
---@return integer
local function next_revision(uri)
  revisions[uri] = (revisions[uri] or 0) + 1
  return revisions[uri]
end

---@param uri string
local function cancel_pending(uri)
  local request = pending[uri]
  if request then
    request.timer:stop()
    request.timer:close()
    pending[uri] = nil
  end
end

---@param params table
---@param dispatchers table
---@param revision integer
local function publish(params, dispatchers, revision)
  local uri = assert(params_uri(params), "missing text document URI")
  local source = params_source(params)
  cache.when_ready(function()
    if revisions[uri] ~= revision then
      return
    end
    dispatchers.notification("textDocument/publishDiagnostics", {
      uri = uri,
      diagnostics = analyze(source, uri),
    })
  end)
end

---@param params table
---@param dispatchers table
function M.publish(params, dispatchers)
  local uri = assert(params_uri(params), "missing text document URI")
  document_dispatchers[uri] = dispatchers
  cancel_pending(uri)
  publish(params, dispatchers, next_revision(uri))
end

---@param params table
---@param dispatchers table
function M.schedule(params, dispatchers)
  local uri = assert(params_uri(params), "missing text document URI")
  document_dispatchers[uri] = dispatchers
  local revision = next_revision(uri)
  cancel_pending(uri)

  local timer = assert(vim.uv.new_timer(), "failed to create diagnostics debounce timer")
  local request = {
    timer = timer,
    params = params,
    dispatchers = dispatchers,
    revision = revision,
  }
  pending[uri] = request
  timer:start(
    DEBOUNCE_MS,
    0,
    vim.schedule_wrap(function()
      if pending[uri] ~= request then
        return
      end
      cancel_pending(uri)
      publish(request.params, request.dispatchers, request.revision)
    end)
  )
end

---Refresh diagnostics for an open buffer without requiring a text change.
---@param bufnr integer?
function M.refresh(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local uri = vim.uri_from_bufnr(bufnr)
  local dispatchers = document_dispatchers[uri]
  if dispatchers then
    M.publish({ textDocument = { uri = uri, text = buffer_source(uri) } }, dispatchers)
  end
end

---@param params lsp.DidCloseTextDocumentParams
---@param dispatchers table
function M.clear(params, dispatchers)
  local uri = params.textDocument.uri
  next_revision(uri)
  cancel_pending(uri)
  document_dispatchers[uri] = nil
  dispatchers.notification("textDocument/publishDiagnostics", {
    uri = uri,
    diagnostics = {},
  })
end

return M
