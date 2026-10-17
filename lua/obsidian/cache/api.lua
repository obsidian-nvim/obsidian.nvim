local fs_util = require "obsidian.util.fs"
local attachment = require "obsidian.attachment"
local link = require "obsidian.link"
local M = {}

---@param target string?
---@return boolean
local function is_external_target(target)
  return target == nil or target == "" or target:match "^%a[%w+.-]*:" ~= nil
end

---@param target string
---@return string
local function normalize_link_target(target)
  target = vim.uri_decode(target):gsub("\\", "/")
  while vim.startswith(target, "./") do
    target = target:sub(3)
  end
  return (target:gsub("^/+", ""))
end

---@param path string
---@param lookup table<string, boolean>
local function add_lookup_path(path, lookup)
  local cache = require "obsidian.cache"
  local path_no_ext = path:gsub("%.md$", "")
  local rel_path = cache.notes.rel_path(path)
  local rel_path_no_ext = rel_path:gsub("%.md$", "")
  local basename = vim.fn.fnamemodify(path, ":t")
  for _, key in ipairs {
    path,
    path_no_ext,
    rel_path,
    rel_path_no_ext,
    basename,
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
    local absolute_no_ext = absolute:gsub("%.md$", "")
    candidates = { absolute, absolute_no_ext, absolute .. ".md" }
  else
    local normalized = normalize_link_target(target)
    local normalized_no_ext = normalized:gsub("%.md$", "")
    candidates = { normalized, normalized_no_ext, normalized .. ".md" }
  end

  for _, key in ipairs(candidates) do
    if lookup[key:lower()] then
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
local function missing_entry_key(target, source_path, target_path, is_attachment)
  if is_attachment then
    return target_path:lower()
  end

  local decoded = vim.uri_decode(target):gsub("\\", "/")
  if vim.startswith(decoded, "./") or vim.startswith(decoded, "../") then
    return vim.fs.normalize(vim.fs.joinpath(vim.fs.dirname(source_path), decoded)):lower()
  end
  return normalize_link_target(decoded):lower()
end

---@class obsidian.cache.FileCandidateData
---@field attachment? boolean
---@field missing? boolean
---@field references? obsidian.NoteCreationReference[]
---@field target? string

---@class obsidian.cache.FileCandidate
---@field path string
---@field label string
---@field attachment? boolean
---@field missing? boolean
---@field references? obsidian.NoteCreationReference[]
---@field target? string

---@param is_attachment boolean
---@param missing boolean
---@param references obsidian.NoteCreationReference[]?
---@param target string?
---@return obsidian.cache.FileCandidateData
local function file_candidate_data(is_attachment, missing, references, target)
  return {
    attachment = is_attachment,
    missing = missing,
    references = references,
    target = target,
  }
end

---@param opts obsidian.PickerFindOpts|?
---@param on_data fun(candidates: obsidian.cache.FileCandidate[], query: string?)
---@return boolean handled
local function find_files_data(opts, on_data)
  opts = opts or {}
  local cache = require "obsidian.cache"
  if not cache.is_enabled() or opts.include_non_markdown then
    return false
  end

  local show_existing_only = opts.show_existing_only ~= false
  local show_attachments = opts.show_attachments == true
  local dir = opts.dir and vim.fs.normalize(tostring(opts.dir)) or vim.fs.normalize(tostring(Obsidian.dir))
  if not fs_util.is_subpath(dir, tostring(Obsidian.dir)) then
    return false
  end

  cache.when_ready(function()
    local query = opts.query and vim.trim(opts.query) or nil
    if query == "" then
      query = nil
    end
    local query_lower = query and string.lower(query) or nil

    ---@type obsidian.cache.FileCandidate[]
    local entries = {}
    local lookup = {}
    ---@type table<string, obsidian.cache.FileCandidate>
    local missing_entries = {}
    local notes = cache.notes.all()
    local attachments = cache.attachments.all()

    ---@param label string
    ---@param path string
    ---@param data obsidian.cache.FileCandidateData
    ---@return obsidian.cache.FileCandidate?
    local function add_entry(label, path, data)
      if query_lower and not string.find(string.lower(label), query_lower, 1, true) then
        return
      end
      local entry = vim.tbl_extend("force", {}, data, { label = label, path = path })
      entries[#entries + 1] = entry
      return entry
    end

    for path, note in pairs(notes) do
      add_lookup_path(path, lookup)
      for _, alias in ipairs(note.aliases or {}) do
        lookup[alias:lower()] = true
      end
    end
    for path in pairs(attachments) do
      add_lookup_path(path, lookup)
    end

    for path, note in pairs(notes) do
      if fs_util.is_subpath(path, dir) then
        local rel_path = cache.notes.rel_path(path):gsub("%.md$", "")
        local data = file_candidate_data(false, false)
        add_entry(rel_path, path, data)
        for _, alias in ipairs(note.aliases or {}) do
          add_entry(rel_path .. " | " .. alias, path, data)
        end
      end
    end
    if show_attachments then
      for path in pairs(attachments) do
        if fs_util.is_subpath(path, dir) then
          add_entry(cache.attachments.rel_path(path), path, file_candidate_data(true, false))
        end
      end
    end

    if not show_existing_only then
      for path, note in pairs(notes) do
        for _, outgoing in ipairs(note.links_out or {}) do
          local target = outgoing.target
          if not is_external_target(target) and not target_exists(target, lookup, path) then
            local missing_is_attachment = attachment.is_attachment_path(target:lower())
            if show_attachments or not missing_is_attachment then
              local target_path = link.missing_link_path(target, path)
              if target_path and fs_util.is_subpath(target_path, dir) then
                local missing_key = missing_entry_key(target, path, target_path, missing_is_attachment)
                ---@type obsidian.NoteCreationReference
                local reference = {
                  filename = path,
                  lnum = outgoing.line or 1,
                  col = outgoing.col or 1,
                  raw = outgoing.raw or target,
                }
                local entry = missing_entries[missing_key]
                if entry then
                  entry.references[#entry.references + 1] = reference
                else
                  local text = normalize_link_target(target)
                  local added = add_entry(
                    text,
                    target_path,
                    file_candidate_data(
                      missing_is_attachment,
                      true,
                      { reference },
                      vim.uri_decode(target):gsub("\\", "/")
                    )
                  )
                  if added then
                    missing_entries[missing_key] = added
                  end
                end
              end
            end
          end
        end
      end
    end

    local pick_query = opts.query
    if query and #entries > 0 then
      pick_query = nil
    end

    on_data(entries, pick_query)
  end)

  return true
end

M.find_files_data = find_files_data

---Compatibility wrapper; picker composition lives in `obsidian.interfaces.notes`.
---@param opts obsidian.PickerFindOpts|?
---@return boolean handled
M.find_files = function(opts)
  opts = opts or {}
  local cache = require "obsidian.cache"
  if not cache.is_enabled() or opts.include_non_markdown then
    return false
  end
  local dir = opts.dir and vim.fs.normalize(tostring(opts.dir)) or vim.fs.normalize(tostring(Obsidian.dir))
  if not fs_util.is_subpath(dir, tostring(Obsidian.dir)) then
    return false
  end
  return require("obsidian.interfaces.notes").find_files(opts)
end

return M
