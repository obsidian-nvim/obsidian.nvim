local Path = require "obsidian.path"
local api = require "obsidian.api"
local async = require "obsidian.async"
local attachment = require "obsidian.attachment"
local filetypes = require "obsidian.filetypes"
local fs_util = require "obsidian.util.fs"
local Handle = require "obsidian.search.handle"
local link_refs = require "obsidian.search.link_refs"
local log = require "obsidian.log"
local note_matcher = require "obsidian.search.note_matcher"
local Opts = require "obsidian.search.opts"
local Ripgrep = require "obsidian.search.ripgrep"

local M = {}

---@param dir string|obsidian.Path
---@return string
local function matching_root(dir)
  local resolved_dir = tostring(Path.new(dir):resolve { strict = true })
  local workspace = Obsidian and api.find_workspace(resolved_dir) or nil
  if workspace then
    return tostring(Path.new(workspace.root):resolve { strict = true })
  end

  if Obsidian and Obsidian.dir then
    local vault_root = tostring(Path.new(Obsidian.dir):resolve { strict = true })
    if fs_util.is_subpath(resolved_dir, vault_root) then
      return vault_root
    end
  end
  return resolved_dir
end

---Find notes by structured identity, heading, or block fields.
---@param term string
---@param callback fun(notes: obsidian.Note[], err: string?)
---@param opts obsidian.search.FindNotesOpts|?
---@return obsidian.search.AsyncHandle
M.find_notes_async = function(term, callback, opts)
  opts = opts or {}
  local dir = opts.dir or api.resolve_workspace_dir()
  local cancelled = false

  async.run(function()
    local Note = require "obsidian.note"
    local root = matching_root(dir)
    local parse_opts = note_matcher.parse_opts(opts)

    local paths_found = {} ---@type string[]
    local ignore_case = opts.ignore_case
    if ignore_case == nil then
      ignore_case = Opts.should_ignore_case(term)
    end
    async.await(5, Ripgrep.find_async, dir, nil, {
      sort_by = opts.sort_by,
      sort_reversed = opts.sort_reversed,
      include_non_markdown = false,
    }, function(path)
      paths_found[#paths_found + 1] = path
    end)

    if cancelled then
      return
    end

    local notes_by_path = {}
    local err_count = 0
    local first_err, first_err_path
    async.join(
      10,
      vim.tbl_map(function(path)
        return function()
          if cancelled then
            return
          end
          local ok, note = pcall(Note.from_file, path, parse_opts)
          if ok then
            if note_matcher.matches(path, root, note, term, opts.match, ignore_case) then
              notes_by_path[path] = note
            end
          else
            err_count = err_count + 1
            if not first_err then
              first_err, first_err_path = note, path
            end
          end
        end
      end, paths_found)
    )

    if cancelled then
      return
    end

    local notes = {}
    for _, path in ipairs(paths_found) do
      if notes_by_path[path] then
        notes[#notes + 1] = notes_by_path[path]
      end
    end

    if first_err ~= nil and first_err_path ~= nil then
      log.err(
        "%d error(s) occurred during search. First error from note at '%s':\n%s",
        err_count,
        first_err_path,
        first_err
      )
    end
    callback(notes)
  end, function(err)
    if err and not cancelled then
      callback({}, tostring(err))
    end
  end)

  return Handle.new(function()
    cancelled = true
  end)
end

---Find attachment paths matching a filename or vault-relative path.
---@param term string
---@param callback fun(paths: string[], err: string?)
---@param opts obsidian.search.FindAttachmentsOpts|?
---@return obsidian.search.AsyncHandle
M.find_attachments_async = function(term, callback, opts)
  opts = opts or {}
  local dir = opts.dir or api.resolve_workspace_dir()
  local root = matching_root(dir)
  local paths = {}
  local query = vim.trim(term or "")
  local ignore_case = Opts.should_ignore_case(query)
  if ignore_case then
    query = query:lower()
  end

  return Ripgrep.find_async(dir, nil, {
    sort_by = opts.sort_by,
    sort_reversed = opts.sort_reversed,
    include_non_markdown = true,
  }, function(path)
    if filetypes.is_attachment(path) then
      local rel = fs_util.relpath(root, path) or path
      if ignore_case then
        rel = rel:lower()
      end
      if query == "" or rel:find(query, 1, true) then
        paths[#paths + 1] = path
      end
    end
  end, function()
    callback(paths)
  end)
end

---@param target string?
---@return boolean
local function ref_target_is_external(target)
  return target == nil or target == "" or target:match "^%a[%w+.-]*:" ~= nil
end

---@param target string
---@return string
local function normalize_ref_target(target)
  target = vim.uri_decode(target):gsub("\\", "/")
  while vim.startswith(target, "./") do
    target = target:sub(3)
  end
  return (target:gsub("^/+", ""))
end

---@param path string
---@param root string
---@param lookup table<string, boolean>
local function add_ref_lookup_path(path, root, lookup)
  local path_no_ext = note_matcher.without_note_extension(path)
  local rel = fs_util.relpath(root, path) or path
  local rel_no_ext = note_matcher.without_note_extension(rel)
  for _, key in ipairs {
    path,
    path_no_ext,
    rel,
    rel_no_ext,
    vim.fs.basename(path),
    vim.fn.fnamemodify(path, ":t:r"),
  } do
    lookup[key:lower()] = true
  end
end

---@param target string
---@param lookup table<string, boolean>
---@param source_path string
---@return boolean
local function ref_target_exists(target, lookup, source_path)
  local decoded = vim.uri_decode(target):gsub("\\", "/")
  local candidates
  if vim.startswith(decoded, "./") or vim.startswith(decoded, "../") then
    local absolute = vim.fs.normalize(vim.fs.joinpath(vim.fs.dirname(source_path), decoded))
    local no_ext = note_matcher.without_note_extension(absolute)
    candidates = { absolute, no_ext, absolute .. ".md" }
  else
    local normalized = normalize_ref_target(decoded)
    local no_ext = note_matcher.without_note_extension(normalized)
    candidates = { normalized, no_ext, normalized .. ".md" }
  end
  for _, candidate in ipairs(candidates) do
    if lookup[candidate:lower()] then
      return true
    end
  end
  return false
end

---@param target string
---@param source_path string
---@param target_path string
---@param is_attachment boolean
---@return string
local function unresolved_ref_key(target, source_path, target_path, is_attachment)
  if is_attachment then
    return target_path:lower()
  end
  local decoded = vim.uri_decode(target):gsub("\\", "/")
  if vim.startswith(decoded, "./") or vim.startswith(decoded, "../") then
    return vim.fs.normalize(vim.fs.joinpath(vim.fs.dirname(source_path), decoded)):lower()
  end
  return normalize_ref_target(decoded):lower()
end

---@async
---@param term string
---@param dir string|obsidian.Path
---@param opts obsidian.search.FindRefsOpts
---@return obsidian.Ref[]
local function find_refs(term, dir, opts)
  local scope = tostring(Path.new(dir):resolve { strict = true })
  local root = matching_root(scope)
  local include_notes = opts.include_notes ~= false
  local include_attachments = opts.include_attachments == true
  local include_unresolved = opts.include_unresolved == true
  local catalog_dir = include_unresolved and root or scope
  local notes = {}
  if include_notes or include_unresolved then
    notes = async.await(2, M.find_notes_async, "", nil, { dir = catalog_dir })
  end
  local attachments = {}
  if include_attachments or include_unresolved then
    attachments = async.await(2, M.find_attachments_async, "", nil, { dir = catalog_dir })
  end
  local query = vim.trim(term or "")
  local ignore_case = Opts.should_ignore_case(query)
  if ignore_case then
    query = query:lower()
  end

  local lookup = {}
  ---@type obsidian.Ref[]
  local refs = {}
  ---@type table<string, obsidian.Ref>
  local unresolved = {}

  ---@param ref obsidian.Ref
  ---@return obsidian.Ref?
  local function add_ref(ref)
    local text = ignore_case and ref.text:lower() or ref.text
    if query ~= "" and not text:find(query, 1, true) then
      return
    end
    refs[#refs + 1] = ref
    return ref
  end

  for _, note in ipairs(notes) do
    local path = tostring(note.path)
    add_ref_lookup_path(path, root, lookup)
    for _, alias in ipairs(note.aliases or {}) do
      lookup[alias:lower()] = true
    end
    if include_notes and fs_util.is_subpath(path, scope) then
      local rel = fs_util.relpath(root, path) or path
      local text = note_matcher.without_note_extension(rel)
      add_ref { kind = "note", text = text, path = path, note = note, attachment = false }
      for _, alias in ipairs(note.aliases or {}) do
        add_ref {
          kind = "note",
          text = text .. " | " .. alias,
          path = path,
          note = note,
          attachment = false,
        }
      end
    end
  end

  for _, path in ipairs(attachments) do
    add_ref_lookup_path(path, root, lookup)
    if include_attachments and fs_util.is_subpath(path, scope) then
      add_ref {
        kind = "attachment",
        text = fs_util.relpath(root, path) or path,
        path = path,
        attachment = true,
      }
    end
  end

  if include_unresolved then
    local note_paths = {}
    for _, note in ipairs(notes) do
      local path = tostring(note.path)
      if fs_util.is_subpath(path, scope) then
        note_paths[#note_paths + 1] = path
      end
    end

    local candidates = {}
    if Ripgrep._has_ripgrep() then
      local seen = {}
      local code = async.await(1, function(done)
        Ripgrep.search_async(scope, { "[[", "](" }, {
          fixed_strings = true,
          max_count_per_file = 1,
        }, function(match)
          local path = match.path.text
          if not Path.new(path):is_absolute() then
            path = vim.fs.joinpath(root, path)
          end
          path = vim.fs.normalize(path)
          if not seen[path] then
            seen[path] = true
            candidates[#candidates + 1] = path
          end
        end, vim.schedule_wrap(done))
      end)
      if code and code > 1 then
        candidates = note_paths
      end
    else
      candidates = note_paths
    end

    local outgoing_by_path = {}
    async.join(
      10,
      vim.tbl_map(function(path)
        return function()
          local ok, outgoing = pcall(link_refs.from_file, path)
          if ok then
            outgoing_by_path[path] = outgoing
          end
        end
      end, candidates)
    )

    for _, source_path in ipairs(candidates) do
      for _, outgoing in ipairs(outgoing_by_path[source_path] or {}) do
        local target = outgoing.target
        if not ref_target_is_external(target) and not ref_target_exists(target, lookup, source_path) then
          local target_is_attachment = attachment.is_attachment_path(target:lower())
          if include_attachments or not target_is_attachment then
            local target_path = require("obsidian.link").missing_link_path(target, source_path)
            if target_path and fs_util.is_subpath(target_path, root) then
              local key = unresolved_ref_key(target, source_path, target_path, target_is_attachment)
              ---@type obsidian.NoteCreationReference
              local reference = {
                filename = source_path,
                lnum = outgoing.line or 1,
                col = outgoing.col or 1,
                raw = outgoing.raw or target,
              }
              local existing = unresolved[key]
              if existing then
                local locations = assert(existing.references, "unresolved reference locations are missing")
                locations[#locations + 1] = reference
              else
                local ref = {
                  kind = "unresolved",
                  text = normalize_ref_target(target),
                  path = target_path,
                  target = vim.uri_decode(target):gsub("\\", "/"),
                  attachment = target_is_attachment,
                  references = { reference },
                }
                if add_ref(ref) then
                  unresolved[key] = ref
                end
              end
            end
          end
        end
      end
    end
  end

  table.sort(refs, function(a, b)
    if a.text ~= b.text then
      return a.text < b.text
    end
    return (a.path or "") < (b.path or "")
  end)
  return refs
end

---Find typed note, attachment, and unresolved-link targets.
---@param term string
---@param callback fun(refs: obsidian.Ref[], err: string?)
---@param opts obsidian.search.FindRefsOpts|?
---@return obsidian.search.AsyncHandle
M.find_refs_async = function(term, callback, opts)
  opts = opts or {}
  local dir = opts.dir or api.resolve_workspace_dir()
  local cancelled = false
  async.run(function()
    local refs = find_refs(term, dir, opts)
    if not cancelled then
      callback(refs)
    end
  end, function(err)
    if err and not cancelled then
      callback({}, tostring(err))
    end
  end)
  return Handle.new(function()
    cancelled = true
  end)
end

return M
