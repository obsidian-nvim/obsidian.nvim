local Path = require "obsidian.path"
local api = require "obsidian.api"
local async = require "obsidian.async"
local filetypes = require "obsidian.filetypes"
local fs_util = require "obsidian.util.fs"
local link_refs = require "obsidian.search.link_refs"
local log = require "obsidian.log"
local note_matcher = require "obsidian.search.note_matcher"
local Opts = require "obsidian.search.opts"
local Ripgrep = require "obsidian.search.ripgrep"
local unresolved = require "obsidian.search.unresolved"

local M = {}

---@type async fun(term: string, dir: string|obsidian.Path): obsidian.search.Unresolved[], obsidian.search.Unresolved[]
local find_unresolved

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

---Find notes within one internal search domain.
---@param term string
---@param callback fun(notes: obsidian.Note[], unresolved: obsidian.search.Unresolved[]?)
---@param opts obsidian.search.FindNotesBackendOpts|?
M.find_notes_async = function(term, callback, opts)
  opts = opts or {}
  local dir = opts.dir or api.resolve_workspace_dir()

  async.run(function()
    local Note = require "obsidian.note"
    local root = matching_root(dir)

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

    local notes_by_path = {}
    local err_count = 0
    local first_err, first_err_path
    async.join(
      10,
      vim.tbl_map(function(path)
        return function()
          local ok, note = pcall(Note.from_file, path)
          if ok then
            if note_matcher.matches(path, root, note, term, opts.domain, ignore_case) then
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
    local missing
    if opts.include_unresolved then
      missing = find_unresolved(term, dir)
    end
    callback(notes, missing)
  end, function(err)
    if err then
      log.err("Failed to find notes: %s", err)
      callback {}
    end
  end)
end

---Find attachment paths matching a filename or vault-relative path.
---@param term string
---@param callback fun(paths: string[])
---@param opts obsidian.search.FindAttachmentsOpts|?
local find_attachments_async = function(term, callback, opts)
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

---@async
---@param term string
---@param dir string|obsidian.Path
---@return obsidian.search.Unresolved[] notes
---@return obsidian.search.Unresolved[] attachments
find_unresolved = function(term, dir)
  local scope = tostring(Path.new(dir):resolve { strict = true })
  local root = matching_root(scope)
  local notes = async.await(2, M.find_notes_async, "", nil, { dir = root })
  local attachments = async.await(2, find_attachments_async, "", nil, { dir = root })
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

  local sources = {}
  for _, note in ipairs(notes) do
    local path = tostring(note.path)
    sources[#sources + 1] = {
      path = path,
      aliases = note.aliases,
      links = outgoing_by_path[path],
    }
  end
  return unresolved.collect(term, {
    root = root,
    scope = scope,
    notes = sources,
    attachments = attachments,
  })
end

---Find attachment paths, optionally including unresolved attachment targets.
---@param term string
---@param callback fun(paths: string[], unresolved: obsidian.search.Unresolved[]?)
---@param opts obsidian.search.FindAttachmentsOpts|?
M.find_attachments_async = function(term, callback, opts)
  opts = opts or {}
  if not opts.include_unresolved then
    return find_attachments_async(term, callback, opts)
  end

  async.run(function()
    local paths = async.await(2, find_attachments_async, term, nil, opts)
    local _, missing = find_unresolved(term, opts.dir or api.resolve_workspace_dir())
    callback(paths, missing)
  end, function(err)
    if err then
      log.err("Failed to find attachments: %s", err)
      callback {}
    end
  end)
end

return M
