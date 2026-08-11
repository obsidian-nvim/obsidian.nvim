local api = require "obsidian.api"
local resolver = require "obsidian.link.resolver"
local search = require "obsidian.search"

local M = {}

M.parse_target = resolver.parse_target
M.normalize_target = resolver.normalize_target
M.predict_path = function(location, opts)
  local target = type(location) == "table" and location or resolver.parse_target(location, opts)
  return resolver.predict_path(target, opts)
end
M.build_index = resolver.build_index
M.resolve_from_index = function(location, opts)
  local target = type(location) == "table" and location or resolver.parse_target(location, opts)
  return resolver.resolve_from_index(target, opts)
end

---@param opts obsidian.link.ResolveOpts|?
---@return obsidian.link.ResolveOpts
local function resolve_opts(opts)
  opts = vim.deepcopy(opts or {})
  if not opts.source_path then
    local current = vim.api.nvim_buf_get_name(0)
    opts.source_path = current ~= "" and current or nil
  end
  return opts
end

---@param result obsidian.link.Resolution
---@param opts table
---@return obsidian.link.Resolution
local function hydrate_direct_note(result, opts)
  if
    result.status ~= "resolved"
    or result.target.kind ~= "note"
    or not result.path
    or result.notes
    or not resolver.is_note_path(result.path)
  then
    return result
  end

  local ok, note = pcall(require("obsidian.note").from_file, result.path, opts.notes or {})
  if ok and note then
    result.notes = { note }
    result.entries = { { kind = "note", path = result.path, value = note } }
  end
  return result
end

---@param target obsidian.link.Target
---@param notes obsidian.Note[]
---@param opts obsidian.link.ResolveOpts
---@return obsidian.link.Resolution
local function resolve_notes(target, notes, opts)
  local index = resolver.build_index(notes)
  local indexed_opts = vim.tbl_extend("force", {}, opts, { index = index })
  return resolver.resolve_from_index(target, indexed_opts)
end

--- Resolve a link target using exact path, filename, ID, and alias matches.
--- Fuzzy matching is intentionally left to search and completion APIs.
---
---@param location string
---@param opts obsidian.link.ResolveOpts|?
---@return obsidian.link.Resolution
M.resolve = function(location, opts)
  opts = resolve_opts(opts)
  local target = resolver.parse_target(location, opts)
  local direct = resolver.resolve_from_index(target, opts)
  if direct.status ~= "missing" or target.kind ~= "note" then
    return hydrate_direct_note(direct, opts)
  end

  local notes = search.find_notes(target.normalized, {
    search = { ignore_case = true },
    notes = opts.notes,
    timeout = opts.timeout,
  })
  return resolve_notes(target, notes, opts)
end

--- Resolve a link target asynchronously using exact path, filename, ID, and alias matches.
---
---@param location string
---@param callback fun(result: obsidian.link.Resolution)
---@param opts obsidian.link.ResolveOpts|?
M.resolve_async = function(location, callback, opts)
  opts = resolve_opts(opts)
  local target = resolver.parse_target(location, opts)
  local direct = resolver.resolve_from_index(target, opts)
  if direct.status ~= "missing" or target.kind ~= "note" then
    callback(hydrate_direct_note(direct, opts))
    return
  end

  search.find_notes_async(target.normalized, function(notes)
    callback(resolve_notes(target, notes, opts))
  end, {
    search = { ignore_case = true },
    notes = opts.notes,
  })
end

--- Expected absolute path for a link target that does not exist yet.
--- This function is side-effect free and does not fire note-creation hooks.
---
---@param location string
---@param source_path string|?
---@return string|?
M.missing_link_path = function(location, source_path)
  local opts = resolve_opts { source_path = source_path }
  return resolver.predict_path(resolver.parse_target(location, opts), opts)
end

--- Backwards-compatible path-only resolver.
---@param location string
---@param opts obsidian.link.ResolveOpts|?
---@return string|?
M.resolve_link_path = function(location, opts)
  local result = M.resolve(location, opts)
  if result.status == "resolved" or result.status == "ambiguous" then
    return result.path
  elseif result.status == "missing" and result.target.kind == "attachment" then
    -- Historically attachment links returned their expected path even before
    -- the attachment existed.
    return result.predicted_path
  end
end

--- For gf and other goto file operations to work.
---@param fname string|?
---@return string|?
M.includeexpr = function(fname)
  local cursor_link = api.cursor_link()
  local location = fname

  if cursor_link then
    local parsed_location = require("obsidian.util").parse_link(cursor_link)
    location = parsed_location or location
  end

  if not location then
    return
  end

  return M.resolve_link_path(location)
end

return M
