local attachment = require "obsidian.attachment"
local fs_util = require "obsidian.util.fs"
local note_matcher = require "obsidian.search.note_matcher"
local SearchOpts = require "obsidian.search.opts"

local M = {}

---@param target string?
---@return boolean
local function is_external(target)
  return target == nil or target == "" or target:match "^%a[%w+.-]*:" ~= nil
end

---@param target string
---@return string
local function normalize_target(target)
  target = vim.uri_decode(target):gsub("\\", "/")
  while vim.startswith(target, "./") do
    target = target:sub(3)
  end
  return (target:gsub("^/+", ""))
end

---@param path string
---@param root string
---@param lookup table<string, boolean>
local function add_lookup_path(path, root, lookup)
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
local function target_exists(target, lookup, source_path)
  local decoded = vim.uri_decode(target):gsub("\\", "/")
  local candidates
  if vim.startswith(decoded, "./") or vim.startswith(decoded, "../") then
    local absolute = vim.fs.normalize(vim.fs.joinpath(vim.fs.dirname(source_path), decoded))
    local no_ext = note_matcher.without_note_extension(absolute)
    candidates = { absolute, no_ext, absolute .. ".md" }
  else
    local normalized = normalize_target(decoded)
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
local function unresolved_key(target, source_path, target_path, is_attachment)
  if is_attachment then
    return target_path:lower()
  end
  local decoded = vim.uri_decode(target):gsub("\\", "/")
  if vim.startswith(decoded, "./") or vim.startswith(decoded, "../") then
    return vim.fs.normalize(vim.fs.joinpath(vim.fs.dirname(source_path), decoded)):lower()
  end
  return normalize_target(decoded):lower()
end

---@class obsidian.search.UnresolvedNoteSource
---@field path string
---@field aliases string[]|?
---@field links table[]|?
---@field searchable boolean|?

---Partition unresolved link targets into note and attachment primitives.
---@param term string
---@param opts { root: string, scope: string, notes: obsidian.search.UnresolvedNoteSource[], attachments: string[] }
---@return obsidian.search.Unresolved[] notes
---@return obsidian.search.Unresolved[] attachments
M.collect = function(term, opts)
  local lookup = {}
  for _, note in ipairs(opts.notes) do
    add_lookup_path(note.path, opts.root, lookup)
    for _, alias in ipairs(note.aliases or {}) do
      lookup[alias:lower()] = true
    end
  end
  for _, path in ipairs(opts.attachments) do
    add_lookup_path(path, opts.root, lookup)
  end

  local query = vim.trim(term or "")
  local ignore_case = SearchOpts.should_ignore_case(query)
  if ignore_case then
    query = query:lower()
  end

  ---@type obsidian.search.Unresolved[]
  local missing_notes = {}
  ---@type obsidian.search.Unresolved[]
  local missing_attachments = {}
  ---@type table<string, obsidian.search.Unresolved>
  local seen = {}

  for _, note in ipairs(opts.notes) do
    if note.searchable ~= false and fs_util.is_subpath(note.path, opts.scope) then
      for _, outgoing in ipairs(note.links or {}) do
        local target = outgoing.target
        if not is_external(target) and not target_exists(target, lookup, note.path) then
          local is_attachment = attachment.is_attachment_path(target:lower())
          local target_path = require("obsidian.link").missing_link_path(target, note.path)
          if target_path and fs_util.is_subpath(target_path, opts.scope) then
            local text = normalize_target(target)
            local haystack = ignore_case and text:lower() or text
            if query == "" or haystack:find(query, 1, true) then
              local key = (is_attachment and "attachment:" or "note:")
                .. unresolved_key(target, note.path, target_path, is_attachment)
              local existing = seen[key]
              ---@type obsidian.NoteCreationReference
              local reference = {
                filename = note.path,
                lnum = outgoing.line or 1,
                col = outgoing.col or 1,
                raw = outgoing.raw or target,
              }
              if existing then
                existing.references[#existing.references + 1] = reference
              else
                local unresolved = {
                  text = text,
                  path = target_path,
                  target = vim.uri_decode(target):gsub("\\", "/"),
                  references = { reference },
                }
                seen[key] = unresolved
                local results = is_attachment and missing_attachments or missing_notes
                results[#results + 1] = unresolved
              end
            end
          end
        end
      end
    end
  end

  local function sort(results)
    table.sort(results, function(a, b)
      if a.text ~= b.text then
        return a.text < b.text
      end
      return a.path < b.path
    end)
  end
  sort(missing_notes)
  sort(missing_attachments)
  return missing_notes, missing_attachments
end

return M
