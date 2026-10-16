local api = require "obsidian.api"
local block_ids = require "obsidian.parse.block_id"
local fs_util = require "obsidian.util.fs"
local volatile = require "obsidian.cache.volatile"

local M = {}

---@class obsidian.search.BlockSearchMatch
---@field note obsidian.Note
---@field path string
---@field block obsidian.note.Block
---@field section obsidian.Section
---@field text string
---@field existing boolean
---@field note_index integer
---@field checksum string
---@field bufnr integer?
---@field placement "inline"|"list-item"|"standalone"?
---@field indent string?

---@class obsidian.search.BlockIndexCandidate
---@field owner obsidian.search.BlockIndexOwner
---@field section obsidian.Section
---@field block obsidian.note.Block
---@field text string
---@field existing boolean
---@field searchable_lower string
---@field placement "inline"|"list-item"|"standalone"?
---@field indent string?

---@class obsidian.search.BlockIndexOwner
---@field note obsidian.Note
---@field path string
---@field note_index integer
---@field checksum string
---@field candidates obsidian.search.BlockIndexCandidate[]
---@field bufnr integer?
---@field changedtick integer?

---@class obsidian.search.BlockIndexValue
---@field dir string
---@field workspace obsidian.Workspace
---@field note_opts obsidian.note.LoadOpts
---@field ignore_checker Glob?
---@field parse_path fun(path: string): obsidian.Note?
---@field parse_buffer fun(bufnr: integer): obsidian.Note?
---@field owners_by_path table<string, obsidian.search.BlockIndexOwner>
---@field candidates obsidian.search.BlockIndexCandidate[]
---@field overlays table<string, obsidian.search.BlockIndexOwner>
---@field next_note_index integer

local function normalize_path(path)
  path = vim.fn.resolve(path)
  return vim.fs.normalize(vim.uv.fs_realpath(path) or path)
end

local function block_text(lines, block_id)
  local visible = {}
  for _, line in ipairs(lines) do
    if not (block_id and vim.trim(line) == block_id) then
      if block_id and block_ids.parse(line) == block_id then
        line = line:gsub("%s*" .. vim.pesc(block_id) .. "%s*$", "")
      end
      visible[#visible + 1] = line
    end
  end
  return vim.trim(table.concat(visible, "\n"))
end

local function section_lines(note, section)
  if section.cached_contents then
    return section.cached_contents
  end
  return vim.list_slice(note.contents, section.range.start_row + 1, section.range.end_row)
end

local function note_checksum(note)
  if note.cache_checksum then
    return note.cache_checksum
  end
  return vim.fn.sha256(table.concat(note.contents, "\n"))
end

local function generated_block_id(note, section, text, reserved)
  local salt = 0
  while true do
    local digest =
      vim.fn.sha256(("%s:%d:%d:%s:%d"):format(note.path, section.range.start_row, section.range.end_row, text, salt))
    local id = "^" .. digest:sub(1, 6)
    if not (note.blocks or {})[id] and not reserved[id] then
      reserved[id] = true
      return id
    end
    salt = salt + 1
  end
end

local function block_id_placement(lines, section)
  if section.block_type == "quote" or section.block_type == "table" or section.block_type == "list" then
    return "standalone"
  elseif section.block_type == "list-item" and #lines > 1 then
    return "list-item", lines[#lines]:match "^(%s+)" or (lines[1]:match "^(%s*)" or "") .. "    "
  end
  return "inline"
end

local function build_owner(note, note_index)
  local owner = {
    note = note,
    path = normalize_path(tostring(note.path)),
    note_index = note_index,
    checksum = note_checksum(note),
    candidates = {},
  }
  local existing_by_section = {}
  for _, block in pairs(note.blocks or {}) do
    if block.section then
      existing_by_section[block.section] = block
    end
  end
  local reserved = {}
  for _, section in ipairs(note.block_candidates or {}) do
    local lines = section_lines(note, section)
    local existing = existing_by_section[section]
    local text = block_text(lines, existing and existing.id)
    if text ~= "" then
      local block = existing and vim.tbl_extend("force", existing, { block = text })
        or {
          id = generated_block_id(note, section, text, reserved),
          line = section.range.end_row,
          block = text,
          section = section,
        }
      local placement, indent
      if not existing then
        placement, indent = block_id_placement(lines, section)
      end
      owner.candidates[#owner.candidates + 1] = {
        owner = owner,
        section = section,
        block = block,
        text = text,
        existing = existing ~= nil,
        searchable_lower = vim.fn.tolower(text .. (existing and " " .. existing.id or "")),
        placement = placement,
        indent = indent,
      }
    end
  end
  return owner
end

local function rebuild_candidates(value)
  local owners = vim.tbl_values(value.owners_by_path)
  table.sort(owners, function(a, b)
    return a.note_index < b.note_index
  end)
  value.candidates = {}
  for _, owner in ipairs(owners) do
    vim.list_extend(value.candidates, owner.candidates)
  end
end

local function build_value(context, notes)
  local value = {
    dir = context.dir,
    workspace = context.workspace,
    note_opts = context.note_opts,
    ignore_checker = context.ignore_checker,
    parse_path = context.parse_path,
    parse_buffer = context.parse_buffer,
    owners_by_path = {},
    candidates = {},
    overlays = {},
    next_note_index = #notes + 1,
  }
  for note_index, note in ipairs(notes) do
    local owner = build_owner(note, note_index)
    value.owners_by_path[owner.path] = owner
  end
  rebuild_candidates(value)
  return value
end

local function path_is_allowed(value, path)
  if not api.path_is_note(path, value.workspace) then
    return false
  end
  local relative = fs_util.relpath(value.dir, path)
  return relative ~= nil and (not value.ignore_checker or not value.ignore_checker:check(relative))
end

local function path_is_indexable(value, path)
  local stat = vim.uv.fs_stat(path)
  return stat ~= nil and stat.type == "file" and path_is_allowed(value, path)
end

local function remove_owner(value, path)
  local owner = value.owners_by_path[path]
  value.owners_by_path[path] = nil
  value.overlays[path] = nil
  return owner and owner.note_index or nil
end

local function refresh_owner(value, path, preferred_note_index)
  local old = value.owners_by_path[path]
  local note_index = preferred_note_index or (old and old.note_index)
  value.overlays[path] = nil
  if not path_is_indexable(value, path) then
    value.owners_by_path[path] = nil
    return old ~= nil
  end
  local note = value.parse_path(path)
  if not note then
    value.owners_by_path[path] = nil
    return old ~= nil
  end
  if not note_index then
    note_index = value.next_note_index
    value.next_note_index = value.next_note_index + 1
  end
  local owner = build_owner(note, note_index)
  if owner.path ~= path then
    value.owners_by_path[path] = nil
    value.overlays[owner.path] = nil
  end
  value.owners_by_path[owner.path] = owner
  return true
end

local function event_deleted(event)
  return event.type == "deleted" or event.type == vim.lsp.protocol.FileChangeType.Deleted
end

local function events_touch_dir(dir, events)
  for _, event in ipairs(events) do
    for _, path in ipairs { event.path, event.old_path, event.new_path } do
      if path and fs_util.is_subpath(normalize_path(path), dir) then
        return true
      end
    end
  end
  return false
end

local index = volatile.vault_index {
  version = function(context)
    return context.version
  end,
  matches = function(_, events, context)
    return events_touch_dir(context.dir, events)
  end,
  build = function(context, done)
    context.scan(function(notes, err)
      if err then
        done(nil, err)
      else
        done(build_value(context, notes))
      end
    end)
  end,
  update = function(value, events)
    local changed = false
    for _, event in ipairs(events) do
      if event.type == "renamed" and event.old_path and event.new_path then
        local old_path = normalize_path(event.old_path)
        local new_path = normalize_path(event.new_path)
        local note_index
        if fs_util.is_subpath(old_path, value.dir) then
          note_index = remove_owner(value, old_path)
          changed = note_index ~= nil or changed
        end
        if fs_util.is_subpath(new_path, value.dir) then
          changed = refresh_owner(value, new_path, note_index) or changed
        end
      elseif event.path then
        local path = normalize_path(event.path)
        if fs_util.is_subpath(path, value.dir) then
          if event_deleted(event) then
            changed = remove_owner(value, path) ~= nil or changed
          else
            changed = refresh_owner(value, path) or changed
          end
        end
      end
    end
    if changed then
      rebuild_candidates(value)
    end
    return true
  end,
}

local function active_overlays(value)
  local active = {}
  local overlay_index = 0
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      local path = name ~= "" and normalize_path(name) or nil
      if path and fs_util.is_subpath(path, value.dir) and path_is_allowed(value, path) then
        local base = value.owners_by_path[path]
        local cached = value.overlays[path]
        if not base or vim.bo[bufnr].modified or cached then
          overlay_index = overlay_index + 1
          local changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
          if not cached or cached.bufnr ~= bufnr or cached.changedtick ~= changedtick then
            local note = value.parse_buffer(bufnr)
            cached = note and build_owner(note, base and base.note_index or value.next_note_index + overlay_index - 1)
              or nil
            if cached then
              cached.bufnr = bufnr
              cached.changedtick = changedtick
            end
          end
          if cached then
            active[cached.path] = cached
          end
        end
      end
    end
  end
  value.overlays = active
  return active
end

local function to_match(candidate)
  local owner = candidate.owner
  return {
    note = owner.note,
    path = owner.path,
    block = candidate.block,
    section = candidate.section,
    text = candidate.text,
    existing = candidate.existing,
    note_index = owner.note_index,
    checksum = owner.checksum,
    bufnr = owner.bufnr or owner.note.bufnr,
    placement = candidate.placement,
    indent = candidate.indent,
  }
end

local function matches(candidate, lowered_query, opts)
  local section = candidate.section
  return (opts.include_unlabeled ~= false or candidate.existing)
    and candidate.searchable_lower:find(lowered_query, 1, true) ~= nil
    and not (
      opts.source_path == candidate.owner.path
      and opts.source_row ~= nil
      and section.range.start_row <= opts.source_row
      and opts.source_row < section.range.end_row
    )
end

---@param query string
---@param notes obsidian.Note[]
---@param opts { source_path: string?, source_row: integer?, include_unlabeled: boolean? }|?
---@return obsidian.search.BlockSearchMatch[]
function M.from_notes(query, notes, opts)
  opts = opts or {}
  local lowered_query = vim.fn.tolower(query)
  local results = {}
  for note_index, note in ipairs(notes) do
    local owner = build_owner(note, note_index)
    for _, candidate in ipairs(owner.candidates) do
      if matches(candidate, lowered_query, opts) then
        results[#results + 1] = to_match(candidate)
      end
    end
  end
  return results
end

---@param query string
---@param callback fun(matches: obsidian.search.BlockSearchMatch[])
---@param context table
function M.find(query, callback, context)
  index:get(context.dir, context, function(value)
    if not value then
      callback {}
      return
    end
    local lowered_query = vim.fn.tolower(query)
    local overlays = active_overlays(value)
    local results = {}
    for _, candidate in ipairs(value.candidates) do
      if not overlays[candidate.owner.path] and matches(candidate, lowered_query, context) then
        results[#results + 1] = to_match(candidate)
      end
    end
    local owners = vim.tbl_values(overlays)
    table.sort(owners, function(a, b)
      return a.note_index < b.note_index
    end)
    for _, owner in ipairs(owners) do
      for _, candidate in ipairs(owner.candidates) do
        if matches(candidate, lowered_query, context) then
          results[#results + 1] = to_match(candidate)
        end
      end
    end
    callback(results)
  end)
end

return M
