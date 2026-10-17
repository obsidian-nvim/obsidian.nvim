local Path = require "obsidian.path"
local search = require "obsidian.search"
local attachment = require "obsidian.attachment"
local api = require "obsidian.api"
local parser = require "obsidian.link.parser"
local uri = require "obsidian.uri"
local fs_util = require "obsidian.util.fs"

local M = {
  parse = parser.parse,
  format = parser.format,
}

---@param path string|obsidian.Path
---@return obsidian.Path
local function normalize_path(path)
  return Path.new(path):resolve()
end

---@param target string
---@return string
local function decode_link_target(target)
  return vim.uri_decode(target):gsub("\\", "/")
end

---@param target string
---@return string
local function normalize_link_target(target)
  target = decode_link_target(target)
  while vim.startswith(target, "./") do
    target = target:sub(3)
  end
  return (target:gsub("^/+", ""))
end

---@param location string
---@param source_file string|?
---@return string|?
local function missing_attachment_path(location, source_file)
  local target = decode_link_target(location)
  if target == "" then
    return nil
  end

  local source_dir = source_file and source_file ~= "" and Path.new(vim.fs.dirname(source_file)) or nil
  local candidates = {}
  if vim.startswith(target, "/") then
    candidates[1] = Obsidian.dir / target:sub(2)
  elseif target:find("/", 1, true) then
    if source_dir then
      candidates[#candidates + 1] = source_dir / target
    end
    candidates[#candidates + 1] = Obsidian.dir / target
  else
    return vim.fs.normalize(attachment.resolve_attachment_path(target, source_file))
  end

  for _, candidate in ipairs(candidates) do
    local abs = vim.fs.normalize(tostring(candidate:resolve()))
    if fs_util.is_subpath(abs, tostring(Obsidian.dir)) then
      return abs
    end
  end
end

---@param location string
---@param source_file string|?
---@return string|?
local function missing_note_path(location, source_file)
  local target = decode_link_target(location)
  if target == "" or vim.endswith(target, "/") then
    return nil
  end

  local opts = { check_invalid_filename = false, source_path = source_file }
  if vim.startswith(target, "/") then
    opts.id = target
  elseif source_file and (vim.startswith(target, "./") or vim.startswith(target, "../")) then
    opts.id = vim.fs.basename(target)
    opts.dir = tostring((Path.new(vim.fs.dirname(source_file)) / vim.fs.dirname(target)):resolve())
  else
    opts.id = normalize_link_target(target)
  end

  local Note = require "obsidian.note"
  local _, path = Note._resolve_id_path(opts)
  return vim.fs.normalize(tostring(path))
end

--- Expected absolute path for a link target that does not exist yet.
---
---@param location string
---@param source_file string|? Absolute path to the note containing the link.
---@return string|?
M.missing_link_path = function(location, source_file)
  if uri.is_uri(location) then
    return nil
  end

  location = parser.parse(location)

  if location == "" then
    return
  end

  if attachment.is_attachment_path(location) then
    return missing_attachment_path(location, source_file)
  end

  return missing_note_path(location, source_file)
end

--- TODO: use in definition handler later,

---@param location string
---@param source_path string|? path of the note containing the link, used to resolve relative paths.
---@return string|?
M.resolve_link_path = function(location, source_path)
  if uri.is_uri(location) then
    return nil
  end

  location = parser.parse(location)

  if location == "" then
    return
  end

  if attachment.is_attachment_path(location) then
    local path = attachment._resolve(location, { filename = source_path })
    if path then
      return tostring(normalize_path(path))
    end
    return nil
  end

  local current_path = source_path or vim.api.nvim_buf_get_name(0)
  local current_dir = current_path ~= "" and vim.fs.dirname(current_path) or nil
  local workspace_dir = api.resolve_workspace_dir(current_path ~= "" and current_path or nil)

  -- Prefer an exact note next to the source over a same-named note elsewhere.
  if current_dir and not Path.new(location):is_absolute() then
    local source_location = location
    if
      not vim.endswith(source_location, ".md")
      and not vim.endswith(source_location, ".qmd")
      and not vim.endswith(source_location, ".base")
    then
      source_location = source_location .. ".md"
    end
    local source_candidate = Path.new(current_dir) / source_location
    if source_candidate:is_file() then
      return tostring(normalize_path(source_candidate))
    end
  end

  local notes = search.resolve_note(location, {
    dir = workspace_dir,
    buf_dir = current_dir,
  })

  if not vim.tbl_isempty(notes) and notes[1] ~= nil then
    return tostring(notes[1].path)
  end
end

---@class obsidian.LinkTargetPreview
---@field kind "url"|"file"|"note"|"ambiguous"|"missing"
---@field url string|?
---@field path string|?
---@field notes obsidian.Note[]|?
---@field anchor string|?
---@field block string|?
---@field error string|?

---Resolve a link target for preview without opening, prompting, or creating anything.
---@param reference string
---@param opts { bufnr: integer?, source_path: string?, workspace_dir: string? }|?
---@param callback fun(target: obsidian.LinkTargetPreview)
M.resolve_target_async = function(reference, opts, callback)
  opts = opts or {}
  local parsed = require("obsidian.parse.refs").parse(reference)
  if not parsed then
    callback { kind = "missing", error = "Invalid link" }
    return
  end

  local location = parsed.target or ""
  local anchor, block = parsed.anchor, parsed.block
  local bufnr = opts.bufnr
  local source_path = opts.source_path
    or (bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr))
    or vim.api.nvim_buf_get_name(0)
  local workspace_dir = opts.workspace_dir or api.resolve_workspace_dir(source_path ~= "" and source_path or nil)

  local function finish_notes(notes)
    if block then
      notes = vim.tbl_filter(function(note)
        return note:resolve_block(block) ~= nil
      end, notes)
    elseif anchor then
      local anchor_link = vim.startswith(anchor, "#") and anchor or ("#" .. anchor)
      notes = vim.tbl_filter(function(note)
        return note:resolve_anchor_link(anchor_link) ~= nil
      end, notes)
    end

    if #notes == 1 then
      callback { kind = "note", notes = notes, anchor = anchor, block = block }
    elseif #notes > 1 then
      callback { kind = "ambiguous", notes = notes, anchor = anchor, block = block }
    else
      callback {
        kind = "missing",
        path = M.missing_link_path(location, source_path),
        anchor = anchor,
        block = block,
        error = (anchor or block) and "Target section not found" or "Target not found",
      }
    end
  end

  if location ~= "" then
    local is_uri, scheme = uri.is_uri(location)
    if is_uri and scheme ~= "file" then
      callback { kind = "url", url = location }
      return
    elseif is_uri and scheme == "file" then
      location = vim.uri_to_fname(location)
    end

    local decoded = decode_link_target(location)
    local candidates = {}
    if Path.new(decoded):is_absolute() then
      candidates[#candidates + 1] = decoded
    else
      if source_path ~= "" then
        candidates[#candidates + 1] = vim.fs.joinpath(vim.fs.dirname(source_path), decoded)
      end
      candidates[#candidates + 1] = vim.fs.joinpath(tostring(workspace_dir), decoded)
    end
    for _, candidate in ipairs(candidates) do
      local stat = vim.uv.fs_stat(candidate)
      local extension = vim.fn.fnamemodify(candidate, ":e"):lower()
      if stat and (stat.type == "directory" or (extension ~= "md" and extension ~= "qmd" and extension ~= "base")) then
        callback { kind = "file", path = candidate, anchor = anchor, block = block }
        return
      end
    end
  else
    local Note = require "obsidian.note"
    local ok, note
    if bufnr and vim.api.nvim_buf_is_loaded(bufnr) then
      ok, note = pcall(Note.from_buffer, bufnr)
    elseif source_path ~= "" and vim.uv.fs_stat(source_path) then
      ok, note = pcall(Note.from_file, source_path)
    end
    if ok and note then
      finish_notes { note }
    else
      callback { kind = "missing", error = "Source note is unavailable" }
    end
    return
  end

  search.resolve_note_async(location, finish_notes, {
    dir = workspace_dir,
    buf_dir = source_path ~= "" and vim.fs.dirname(source_path) or nil,
    notes = { collect_anchor_links = anchor ~= nil, collect_blocks = block ~= nil },
  })
end

--- For gf and other goto file operations to work.
---@param fname string|?
---@return string|?
M.includeexpr = function(fname)
  local link = api.cursor_link()
  local location = fname

  if link then
    local ref = require("obsidian.parse.refs").parse(link)
    location = ref and ref.target or location
  end

  if not location then
    return
  end

  local decoded = vim.uri_decode(location)
  if decoded then
    ---@cast decoded string
    location = decoded
  end
  return M.resolve_link_path(location)
end

return M
