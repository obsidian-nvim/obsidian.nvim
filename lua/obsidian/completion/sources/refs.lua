--- TODO: make more declarative
local completion = require "obsidian.completion.refs"
local util = require "obsidian.util"
local api = require "obsidian.api"
local search = require "obsidian.search"
local cache = require "obsidian.cache"
local ignore = require "obsidian.ignore"

---@class obsidian.completion.sources.refs.options
---@field label string|?
---@field new_text string
---@field sort_text string|?
---@field documentation table|?
---@field note obsidian.Note|?
---@field anchor obsidian.note.HeaderAnchor|?
---@field block obsidian.note.Block|?
---@field disambiguated boolean|?

---Used to track variables that are used between reusable method calls. This is required, because each
---call to the sources's completion hook won't create a new source object, but will reuse the same one.
---@class obsidian.completion.sources.refs.context
---@field completion_resolve_callback fun(resp: lsp.CompletionList)
---@field request obsidian.completion.Request
---@field in_buffer_only boolean
---@field search string|?
---@field insert_start integer|?
---@field insert_end integer|?
---@field block_link string|?
---@field anchor_link string|?
---@field new_text_to_option table<string, obsidian.completion.sources.refs.options>

local M = {}

---@type lsp.CompletionList
local EMPTY_RESPONSE = {
  isIncomplete = true,
  items = {},
}

---@type integer
local ALL_LINES = 2147483647

---@class obsidian.completion.sources.refs.block_search_index
---@field dir string
---@field candidates obsidian.completion.sources.refs.block_search_candidate[]|?
---@field owners_by_path table<string, obsidian.completion.sources.refs.block_search_owner>|?
---@field overlays table<string, obsidian.completion.sources.refs.block_search_owner>
---@field next_note_idx integer
---@field note_opts obsidian.note.LoadOpts
---@field workspace obsidian.Workspace
---@field ignore_checker Glob|?

---@class obsidian.completion.sources.refs.block_search_owner
---@field note obsidian.Note
---@field path string
---@field note_idx integer
---@field checksum string
---@field candidates obsidian.completion.sources.refs.block_search_candidate[]
---@field bufnr integer|?
---@field changedtick integer|?

---@class obsidian.completion.sources.refs.block_search_candidate
---@field owner obsidian.completion.sources.refs.block_search_owner
---@field section obsidian.Section
---@field block obsidian.note.Block
---@field existing boolean
---@field searchable_lower string
---@field label string
---@field sort_text string
---@field placement "inline"|"list-item"|"standalone"|?
---@field indent string|?

---@class obsidian.completion.sources.refs.new_block_target
---@field path string
---@field bufnr integer|?
---@field range lsp.Range
---@field checksum string
---@field placement "inline"|"list-item"|"standalone"
---@field indent string|?

---@class obsidian.completion.sources.refs.block_item_spec
---@field note obsidian.Note
---@field block obsidian.note.Block
---@field label string
---@field sort_text string
---@field link string
---@field new_target obsidian.completion.sources.refs.new_block_target|?

---@class obsidian.completion.sources.refs.block_search_request
---@field cc obsidian.completion.sources.refs.context
---@field query string
---@field dir obsidian.Path
---@field dir_key string
---@field note_opts obsidian.note.LoadOpts

---@class obsidian.completion.sources.refs.block_file_event
---@field type integer|string
---@field path string|?
---@field old_path string|?
---@field new_path string|?

---@type table<string, obsidian.completion.sources.refs.block_search_index>
local vault_block_search_indexes = {}
---@type table<string, obsidian.completion.sources.refs.block_search_request>
local vault_block_search_pending = {}
local vault_block_search_generation = 0

--- Returns whether it's possible to complete the search and sets up the search related variables in cc
---@param cc obsidian.completion.sources.refs.context
---@return boolean success provides a chance to return early if the request didn't meet the requirements
local function can_complete_request(cc)
  local can_complete
  can_complete, cc.search, cc.insert_start, cc.insert_end = completion.can_complete(cc.request)

  if
    not (
      can_complete
      and cc.search ~= nil
      and (
        completion.block_search(cc.search) ~= nil
        or completion.heading_search(cc.search) ~= nil
        or #cc.search >= Obsidian.opts.completion.min_chars
      )
    )
  then
    return false
  end

  return true
end

---@param note obsidian.Note
---@param section obsidian.Section
---@return obsidian.note.Block|?
local function existing_block(note, section)
  for _, block in pairs(note.blocks or {}) do
    if block.section == section then
      return block
    end
  end
end

---@param lines string[]
---@param block_id string|?
---@return string
local function block_text(lines, block_id)
  local visible = {}
  for _, line in ipairs(lines) do
    if not (block_id and vim.trim(line) == block_id) then
      if block_id and util.parse_block(line) == block_id then
        line = line:gsub("%s*" .. vim.pesc(block_id) .. "%s*$", "")
      end
      visible[#visible + 1] = line
    end
  end
  return vim.trim(table.concat(visible, "\n"))
end

---@param note obsidian.Note
---@param section obsidian.Section
---@param text string
---@param reserved table<string, boolean>
---@return string
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

---@param text string
---@return string
local function block_label(text)
  local label = text:gsub("%s+", " ")
  if vim.fn.strchars(label) > 80 then
    label = vim.fn.strcharpart(label, 0, 79) .. "…"
  end
  return label
end

---@param lines string[]
---@param section obsidian.Section
---@return "inline"|"list-item"|"standalone"
---@return string|? indent
local function block_id_placement(lines, section)
  if section.block_type == "quote" or section.block_type == "table" then
    return "standalone"
  elseif section.block_type == "list" then
    return "standalone"
  elseif section.block_type == "list-item" and #lines > 1 then
    return "list-item", lines[#lines]:match "^(%s+)" or (lines[1]:match "^(%s*)" or "") .. "    "
  end
  return "inline"
end

---@param block obsidian.note.Block
---@return string
local function format_current_block_link(block)
  if Obsidian.opts.link.style == "wiki" then
    return "[[#" .. block.id .. "]]"
  elseif Obsidian.opts.link.style == "markdown" then
    return "[#" .. block.id .. "](#" .. block.id .. ")"
  elseif type(Obsidian.opts.link.style) == "function" then
    return Obsidian.opts.link.style { label = "", path = "", block = block }
  end
  error "not implemented"
end

---@param request obsidian.completion.Request
---@param range lsp.Range
---@return string
local function current_completion_text(request, range)
  local suffix_len = range["end"].character - request.character
  return request.cursor_before_line:sub(range.start.character + 1) .. request.cursor_after_line:sub(1, suffix_len)
end

---@param cc obsidian.completion.sources.refs.context
---@return lsp.Range
---@return string placeholder
---@return string source_path
local function block_completion_request_context(cc)
  local range = {
    start = {
      line = cc.request.line,
      character = assert(cc.insert_start, "block completion insert start is missing"),
    },
    ["end"] = {
      line = cc.request.line,
      character = assert(cc.insert_end, "block completion insert end is missing"),
    },
  }
  local source_name = vim.api.nvim_buf_get_name(cc.request.bufnr)
  local source_path = vim.uv.fs_realpath(vim.fn.resolve(source_name)) or source_name
  source_path = vim.fs.normalize(source_path)
  return range, current_completion_text(cc.request, range), source_path
end

---@param cc obsidian.completion.sources.refs.context
---@param range lsp.Range
---@param placeholder string
---@param spec obsidian.completion.sources.refs.block_item_spec
---@return lsp.CompletionItem
local function make_block_completion_item(cc, range, placeholder, spec)
  ---@type lsp.CompletionItem
  local item = {
    label = spec.label,
    sortText = spec.sort_text,
    filterText = "[[" .. assert(cc.search, "block completion search is missing") .. " " .. spec.label,
    documentation = {
      kind = "markdown",
      value = spec.note:display_info { label = spec.link, block = spec.block },
    },
    kind = vim.lsp.protocol.CompletionItemKind.Reference,
    textEdit = {
      newText = spec.new_target and placeholder or spec.link,
      range = range,
    },
  }

  local target = spec.new_target
  if target then
    item.command = {
      command = "obsidian.block_reference_new",
      title = "Obsidian create block reference",
      arguments = {
        {
          target_path = target.path,
          target_bufnr = target.bufnr,
          target_range = target.range,
          target_checksum = target.checksum,
          block_id = spec.block.id,
          placement = target.placement,
          indent = target.indent,
          source_bufnr = cc.request.bufnr,
          source_range = range,
          source_text = spec.link,
          placeholder = placeholder,
        },
      },
    }
  end

  return item
end

---@param results obsidian.Note[]
---@param dir obsidian.Path
---@param note_opts obsidian.note.LoadOpts
---@param include_unmatched boolean|?
---@return obsidian.Note[]
local function include_loaded_notes(results, dir, note_opts, include_unmatched)
  local path_to_idx = {}
  for idx, note in ipairs(results) do
    path_to_idx[tostring(note.path)] = idx
  end

  local Note = require "obsidian.note"
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local path = vim.uv.fs_realpath(vim.fn.resolve(vim.api.nvim_buf_get_name(bufnr)))
      path = path and vim.fs.normalize(path)
      if path and util.is_subpath(path, tostring(dir)) and api.path_is_note(path) then
        local idx = path_to_idx[path]
        if not idx or vim.bo[bufnr].modified then
          local opts = vim.tbl_extend("force", note_opts, {
            max_lines = vim.api.nvim_buf_line_count(bufnr),
          })
          local note = Note.from_buffer(bufnr, opts)
          idx = path_to_idx[tostring(note.path)]
          if idx then
            results[idx] = note
          elseif include_unmatched ~= false then
            results[#results + 1] = note
            path_to_idx[tostring(note.path)] = #results
          end
        end
      end
    end
  end
  return results
end

---@param cc obsidian.completion.sources.refs.context
---@param scope "current"|"note"|"vault"
---@param query string
---@param results obsidian.Note[]
local function process_block_search_results(cc, scope, query, results)
  local range, placeholder, source_path = block_completion_request_context(cc)
  local lowered_query = vim.fn.tolower(query)
  ---@type lsp.CompletionItem[]
  local items = {}

  for note_idx, note in ipairs(results) do
    local same_note = vim.fs.normalize(tostring(note.path)) == source_path
    local reserved_ids = {}
    for _, section in ipairs(note.block_candidates or {}) do
      if not (same_note and section.range.start_row <= cc.request.line and cc.request.line < section.range.end_row) then
        local lines = vim.list_slice(note.contents, section.range.start_row + 1, section.range.end_row)
        local existing = existing_block(note, section)
        local text = block_text(lines, existing and existing.id)
        local searchable = text .. (existing and " " .. existing.id or "")
        if text ~= "" and vim.fn.tolower(searchable):find(lowered_query, 1, true) then
          local block = existing
            or {
              id = generated_block_id(note, section, text, reserved_ids),
              line = section.range.end_row,
              block = text,
              section = section,
            }
          if existing then
            block = vim.tbl_extend("force", block, { block = text })
          end

          local link = scope == "current" and format_current_block_link(block)
            or note:format_link { label = note:display_name(), block = block }
          local label = block_label(text)
          if existing then
            label = label .. " " .. existing.id
          end
          if scope == "vault" then
            label = label .. " — " .. note:display_name()
          end

          ---@type obsidian.completion.sources.refs.new_block_target?
          local new_target
          if not existing then
            local placement, indent = block_id_placement(lines, section)
            new_target = {
              path = tostring(note.path),
              bufnr = note.bufnr,
              range = {
                start = { line = section.range.start_row, character = 0 },
                ["end"] = { line = section.range.end_row, character = 0 },
              },
              checksum = vim.fn.sha256(table.concat(note.contents, "\n")),
              placement = placement,
              indent = indent,
            }
          end
          items[#items + 1] = make_block_completion_item(cc, range, placeholder, {
            note = note,
            block = block,
            label = label,
            sort_text = ("%08d:%08d"):format(note_idx, section.range.start_row),
            link = link,
            new_target = new_target,
          })
        end
      end
    end
  end

  cc.completion_resolve_callback { isIncomplete = true, items = items }
end

---@param note obsidian.Note
---@param note_idx integer
---@return obsidian.completion.sources.refs.block_search_owner
local function build_vault_block_owner(note, note_idx)
  local path = vim.fs.normalize(tostring(note.path))
  ---@type obsidian.completion.sources.refs.block_search_owner
  local owner = {
    note = note,
    path = path,
    note_idx = note_idx,
    checksum = vim.fn.sha256(table.concat(note.contents, "\n")),
    candidates = {},
  }
  ---@type table<obsidian.Section, obsidian.note.Block>
  local existing_by_section = {}
  for _, block in pairs(note.blocks or {}) do
    if block.section then
      existing_by_section[block.section] = block
    end
  end
  ---@type table<string, boolean>
  local reserved_ids = {}

  for _, section in ipairs(note.block_candidates or {}) do
    local lines = vim.list_slice(note.contents, section.range.start_row + 1, section.range.end_row)
    local existing = existing_by_section[section]
    local text = block_text(lines, existing and existing.id)
    if text ~= "" then
      local block = existing and vim.tbl_extend("force", existing, { block = text })
        or {
          id = generated_block_id(note, section, text, reserved_ids),
          line = section.range.end_row,
          block = text,
          section = section,
        }
      ---@cast block obsidian.note.Block
      local label = block_label(text)
      if existing then
        label = label .. " " .. existing.id
      end
      label = label .. " — " .. note:display_name()
      local placement, indent
      if not existing then
        placement, indent = block_id_placement(lines, section)
      end
      owner.candidates[#owner.candidates + 1] = {
        owner = owner,
        section = section,
        block = block,
        existing = existing ~= nil,
        searchable_lower = vim.fn.tolower(text .. (existing and " " .. existing.id or "")),
        label = label,
        sort_text = ("%08d:%08d"):format(note_idx, section.range.start_row),
        placement = placement,
        indent = indent,
      }
    end
  end

  return owner
end

---@param index obsidian.completion.sources.refs.block_search_index
local function rebuild_vault_block_candidates(index)
  local owners = vim.tbl_values(assert(index.owners_by_path, "vault block index owners are missing"))
  table.sort(owners, function(a, b)
    return a.note_idx < b.note_idx
  end)

  local candidates = {}
  for _, owner in ipairs(owners) do
    vim.list_extend(candidates, owner.candidates)
  end
  index.candidates = candidates
end

---@param index obsidian.completion.sources.refs.block_search_index
---@param notes obsidian.Note[]
local function build_vault_block_index(index, notes)
  ---@type table<string, obsidian.completion.sources.refs.block_search_owner>
  local owners_by_path = {}
  index.owners_by_path = owners_by_path
  index.overlays = {}
  index.next_note_idx = #notes + 1
  for note_idx, note in ipairs(notes) do
    local owner = build_vault_block_owner(note, note_idx)
    owners_by_path[owner.path] = owner
  end
  rebuild_vault_block_candidates(index)
end

---@param path string
---@return string
local function normalize_vault_block_path(path)
  path = vim.fn.resolve(path)
  return vim.fs.normalize(vim.uv.fs_realpath(path) or path)
end

---@param index obsidian.completion.sources.refs.block_search_index
---@param path string
---@return boolean
local function vault_block_path_is_in_index(index, path)
  return util.is_subpath(path, index.dir)
end

---@param index obsidian.completion.sources.refs.block_search_index
---@param path string
---@return boolean
local function vault_block_path_is_indexable(index, path)
  local stat = vim.uv.fs_stat(path)
  if not stat or stat.type ~= "file" then
    return false
  end
  if not api.path_is_note(path, index.workspace) then
    return false
  end
  local relative_path = util.relpath(index.dir, path)
  return relative_path ~= nil and (not index.ignore_checker or not index.ignore_checker:check(relative_path))
end

---@param index obsidian.completion.sources.refs.block_search_index
---@param path string
---@return integer|? removed_note_idx
local function remove_vault_block_owner(index, path)
  local owners_by_path = assert(index.owners_by_path, "vault block index owners are missing")
  local owner = owners_by_path[path]
  owners_by_path[path] = nil
  index.overlays[path] = nil
  return owner and owner.note_idx or nil
end

---@param index obsidian.completion.sources.refs.block_search_index
---@param path string
---@param preferred_note_idx integer|?
---@return boolean changed
local function refresh_vault_block_owner(index, path, preferred_note_idx)
  local owners_by_path = assert(index.owners_by_path, "vault block index owners are missing")
  local old_owner = owners_by_path[path]
  local note_idx = preferred_note_idx or (old_owner and old_owner.note_idx)
  index.overlays[path] = nil

  if not vault_block_path_is_indexable(index, path) then
    owners_by_path[path] = nil
    return old_owner ~= nil
  end

  local Note = require "obsidian.note"
  local ok, note = pcall(Note.from_file, path, index.note_opts)
  if not ok then
    owners_by_path[path] = nil
    return old_owner ~= nil
  end

  if not note_idx then
    note_idx = index.next_note_idx
    index.next_note_idx = index.next_note_idx + 1
  end
  local owner = build_vault_block_owner(note, note_idx)
  if owner.path ~= path then
    owners_by_path[path] = nil
    index.overlays[owner.path] = nil
  end
  owners_by_path[owner.path] = owner
  return true
end

---@param event obsidian.completion.sources.refs.block_file_event
---@return boolean
local function vault_block_event_is_deleted(event)
  return event.type == "deleted" or event.type == vim.lsp.protocol.FileChangeType.Deleted
end

---@param index obsidian.completion.sources.refs.block_search_index
---@param events obsidian.completion.sources.refs.block_file_event[]
---@return boolean changed
local function refresh_vault_block_index(index, events)
  local changed = false
  for _, event in ipairs(events) do
    if event.type == "renamed" and event.old_path and event.new_path then
      local old_path = normalize_vault_block_path(event.old_path)
      local new_path = normalize_vault_block_path(event.new_path)
      local note_idx
      if vault_block_path_is_in_index(index, old_path) then
        note_idx = remove_vault_block_owner(index, old_path)
        changed = note_idx ~= nil or changed
      end
      if vault_block_path_is_in_index(index, new_path) then
        changed = refresh_vault_block_owner(index, new_path, note_idx) or changed
      end
    elseif event.path then
      local path = normalize_vault_block_path(event.path)
      if vault_block_path_is_in_index(index, path) then
        if vault_block_event_is_deleted(event) then
          changed = remove_vault_block_owner(index, path) ~= nil or changed
        else
          changed = refresh_vault_block_owner(index, path) or changed
        end
      end
    end
  end

  if changed then
    rebuild_vault_block_candidates(index)
  end
  return changed
end

---@param index obsidian.completion.sources.refs.block_search_index
---@param events obsidian.completion.sources.refs.block_file_event[]
---@return boolean
local function vault_block_events_touch_index(index, events)
  for _, event in ipairs(events) do
    for _, path in ipairs { event.path, event.old_path, event.new_path } do
      if path and vault_block_path_is_in_index(index, normalize_vault_block_path(path)) then
        return true
      end
    end
  end
  return false
end

require("obsidian.lsp.watchfiles").register_handler(function(events)
  local touched = false
  for dir_key, index in pairs(vault_block_search_indexes) do
    if vault_block_events_touch_index(index, events) then
      touched = true
      if index.candidates and index.owners_by_path then
        refresh_vault_block_index(index, events)
      else
        vault_block_search_indexes[dir_key] = nil
      end
    end
  end
  if touched then
    vault_block_search_generation = vault_block_search_generation + 1
  end
end)

---@param index obsidian.completion.sources.refs.block_search_index
---@param dir obsidian.Path
---@param note_opts obsidian.note.LoadOpts
---@return table<string, obsidian.completion.sources.refs.block_search_owner>
local function vault_block_overlays(index, dir, note_opts)
  local owners_by_path = assert(index.owners_by_path, "vault block index owners are missing")
  local Note = require "obsidian.note"
  local active = {}
  local overlay_idx = 0

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local path = vim.uv.fs_realpath(vim.fn.resolve(vim.api.nvim_buf_get_name(bufnr)))
      path = path and vim.fs.normalize(path)
      if path and util.is_subpath(path, tostring(dir)) and api.path_is_note(path) then
        local base = owners_by_path[path]
        local cached = index.overlays[path]
        if not base or vim.bo[bufnr].modified or cached then
          overlay_idx = overlay_idx + 1
          local changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
          local owner = cached
          if not owner or owner.bufnr ~= bufnr or owner.changedtick ~= changedtick then
            local opts = vim.tbl_extend("force", note_opts, {
              max_lines = vim.api.nvim_buf_line_count(bufnr),
            })
            local note = Note.from_buffer(bufnr, opts)
            owner = build_vault_block_owner(note, base and base.note_idx or index.next_note_idx + overlay_idx - 1)
            owner.bufnr = bufnr
            owner.changedtick = changedtick
          end
          active[assert(owner).path] = owner
        end
      end
    end
  end

  index.overlays = active
  return active
end

---@param cc obsidian.completion.sources.refs.context
---@param query string
---@param index obsidian.completion.sources.refs.block_search_index
---@param dir obsidian.Path
---@param note_opts obsidian.note.LoadOpts
local function process_vault_block_search_results(cc, query, index, dir, note_opts)
  local range, placeholder, source_path = block_completion_request_context(cc)
  local lowered_query = vim.fn.tolower(query)
  local overlays = vault_block_overlays(index, dir, note_opts)
  ---@type lsp.CompletionItem[]
  local items = {}

  ---@param candidate obsidian.completion.sources.refs.block_search_candidate
  local function add_match(candidate)
    local owner = candidate.owner
    local section = candidate.section
    local same_note = owner.path == source_path
    if
      not (same_note and section.range.start_row <= cc.request.line and cc.request.line < section.range.end_row)
      and candidate.searchable_lower:find(lowered_query, 1, true)
    then
      local link = owner.note:format_link { label = owner.note:display_name(), block = candidate.block }
      ---@type obsidian.completion.sources.refs.new_block_target?
      local new_target
      if not candidate.existing then
        new_target = {
          path = owner.path,
          bufnr = owner.note.bufnr,
          range = {
            start = { line = section.range.start_row, character = 0 },
            ["end"] = { line = section.range.end_row, character = 0 },
          },
          checksum = owner.checksum,
          placement = assert(candidate.placement, "generated block placement is missing"),
          indent = candidate.indent,
        }
      end
      items[#items + 1] = make_block_completion_item(cc, range, placeholder, {
        note = owner.note,
        block = candidate.block,
        label = candidate.label,
        sort_text = candidate.sort_text,
        link = link,
        new_target = new_target,
      })
    end
  end

  for _, candidate in ipairs(assert(index.candidates, "vault block index candidates are missing")) do
    if not overlays[candidate.owner.path] then
      add_match(candidate)
    end
  end
  local overlay_owners = vim.tbl_values(overlays)
  table.sort(overlay_owners, function(a, b)
    return a.note_idx < b.note_idx
  end)
  for _, owner in ipairs(overlay_owners) do
    for _, candidate in ipairs(owner.candidates) do
      add_match(candidate)
    end
  end

  cc.completion_resolve_callback { isIncomplete = true, items = items }
end

---@param cc obsidian.completion.sources.refs.context
---@return string
local function vault_block_request_key(cc)
  return ("%d:%d:%d"):format(
    cc.request.bufnr,
    cc.request.line,
    assert(cc.insert_start, "vault block completion insert start is missing")
  )
end

---@param cc obsidian.completion.sources.refs.context
local function cancel_pending_vault_block_request(cc)
  local key = vault_block_request_key(cc)
  local pending = vault_block_search_pending[key]
  if pending then
    vault_block_search_pending[key] = nil
    pending.cc.completion_resolve_callback(EMPTY_RESPONSE)
  end
end

---@param cc obsidian.completion.sources.refs.context
---@param query string
---@param dir obsidian.Path
---@param note_opts obsidian.note.LoadOpts
local function queue_vault_block_request(cc, query, dir, note_opts)
  local key = vault_block_request_key(cc)
  local pending = vault_block_search_pending[key]
  if pending then
    vault_block_search_pending[key] = nil
    pending.cc.completion_resolve_callback(EMPTY_RESPONSE)
  end
  vault_block_search_pending[key] = {
    cc = cc,
    query = query,
    dir = dir,
    dir_key = tostring(dir),
    note_opts = note_opts,
  }
end

---@param dir_key string
---@return obsidian.completion.sources.refs.block_search_request[]
local function take_pending_vault_block_requests(dir_key)
  local pending = {}
  for key, request in pairs(vault_block_search_pending) do
    if request.dir_key == dir_key then
      vault_block_search_pending[key] = nil
      pending[#pending + 1] = request
    end
  end
  return pending
end

---@type fun(dir: obsidian.Path, note_opts: obsidian.note.LoadOpts)
local start_vault_block_search_index

start_vault_block_search_index = function(dir, note_opts)
  local dir_key = tostring(dir)
  if vault_block_search_indexes[dir_key] then
    return
  end
  local workspace = assert(api.find_workspace(dir), "vault block completion workspace is missing")
  local workspace_opts = api._workspace_opts(workspace)
  ---@type obsidian.completion.sources.refs.block_search_index
  local index = {
    dir = dir_key,
    overlays = {},
    next_note_idx = 1,
    note_opts = note_opts,
    workspace = workspace,
    ignore_checker = ignore._build_ignore_checker(workspace_opts.file.ignore_filters),
  }
  vault_block_search_indexes[dir_key] = index
  local generation = vault_block_search_generation
  search.find_notes_async("", function(results)
    if generation ~= vault_block_search_generation or vault_block_search_indexes[dir_key] ~= index then
      if vault_block_search_indexes[dir_key] == index then
        vault_block_search_indexes[dir_key] = nil
      end
      if not vault_block_search_indexes[dir_key] then
        local restart_dir, restart_note_opts = dir, note_opts
        for _, request in pairs(vault_block_search_pending) do
          if request.dir_key == dir_key then
            restart_dir, restart_note_opts = request.dir, request.note_opts
            break
          end
        end
        start_vault_block_search_index(restart_dir, restart_note_opts)
      end
      return
    end

    build_vault_block_index(index, results)
    for _, request in ipairs(take_pending_vault_block_requests(dir_key)) do
      process_vault_block_search_results(request.cc, request.query, index, request.dir, request.note_opts)
    end
  end, {
    dir = dir,
    search = { sort = false, include_templates = false, ignore_case = true },
    notes = note_opts,
  })
end

---@param cc obsidian.completion.sources.refs.context
---@param query string
---@param dir obsidian.Path
---@param note_opts obsidian.note.LoadOpts
local function process_vault_block_search(cc, query, dir, note_opts)
  local dir_key = tostring(dir)
  local index = vault_block_search_indexes[dir_key]
  local has_index = index ~= nil
  local should_complete = vim.fn.strchars(query) >= Obsidian.opts.completion.min_chars

  if not should_complete then
    cancel_pending_vault_block_request(cc)
    cc.completion_resolve_callback(EMPTY_RESPONSE)
    if not has_index then
      start_vault_block_search_index(dir, note_opts)
    end
    return
  end

  if not has_index then
    queue_vault_block_request(cc, query, dir, note_opts)
    start_vault_block_search_index(dir, note_opts)
  elseif index.candidates then
    process_vault_block_search_results(cc, query, index, dir, note_opts)
  else
    queue_vault_block_request(cc, query, dir, note_opts)
  end
end

---@param cc obsidian.completion.sources.refs.context
---@param scope "current"|"note"|"vault"
---@param query string
---@param target string|?
local function process_block_search(cc, scope, query, target)
  if scope ~= "vault" and vim.fn.strchars(query) < Obsidian.opts.completion.min_chars then
    cc.completion_resolve_callback(EMPTY_RESPONSE)
    return
  end

  if scope == "current" then
    local note = api.current_note(cc.request.bufnr, {
      max_lines = vim.api.nvim_buf_line_count(cc.request.bufnr),
      collect_blocks = true,
      collect_block_candidates = true,
    })
    process_block_search_results(cc, scope, query, note and { note } or {})
    return
  end

  local dir = api.resolve_workspace_dir()
  local note_opts = { max_lines = ALL_LINES, collect_blocks = true, collect_block_candidates = true }
  local function on_results(results)
    process_block_search_results(cc, scope, query, include_loaded_notes(results, dir, note_opts, false))
  end
  if scope == "note" then
    search.resolve_note_async(
      assert(target, "named-note block search requires a target"),
      on_results,
      { notes = note_opts }
    )
    return
  end
  process_vault_block_search(cc, query, dir, note_opts)
end

---@param query string
---@return obsidian.Note[]
local function cached_heading_notes(query)
  local Note = require "obsidian.note"
  ---@type obsidian.Note[]
  local notes = {}
  ---@type table<string, obsidian.Note>
  local path_to_note = {}
  ---@type table<string, table<string, obsidian.note.HeaderAnchor>>
  local path_to_anchors = {}

  for _, heading in ipairs(cache.notes.find_headings(query)) do
    if api.path_is_note(heading.path) then
      local note = path_to_note[heading.path]
      local anchors = path_to_anchors[heading.path]
      if not note then
        local row = cache.notes.get(heading.path)
        local created = Note.new(row.id or cache.notes.basename(heading.path), row.aliases, nil, heading.path)
        local created_anchors = {}
        rawset(created, "anchor_links", created_anchors)
        path_to_note[heading.path] = created
        path_to_anchors[heading.path] = created_anchors
        notes[#notes + 1] = created
        note = created
        anchors = created_anchors
      end
      anchors[heading.anchor .. ":" .. heading.line] = {
        anchor = heading.anchor,
        header = heading.header,
        level = heading.level,
        line = heading.line,
      }
    end
  end

  return notes
end

---@param anchor obsidian.note.HeaderAnchor
---@return obsidian.note.HeaderAnchor
local function heading_completion_anchor(anchor)
  if Obsidian.opts.link.style ~= "wiki" then
    return anchor
  end

  -- Obsidian-style wiki heading links use the original heading text, but some
  -- characters would instead be parsed as link syntax by our wiki-link parser.
  if anchor.header:find "[|%[%]]" or vim.startswith(anchor.header, "^") then
    return anchor
  end

  local result = vim.tbl_extend("force", anchor, { anchor = "#" .. anchor.header })
  ---@cast result obsidian.note.HeaderAnchor
  return result
end

---@param note obsidian.Note
---@return obsidian.note.HeaderAnchor[]
local function note_headings(note)
  local headings = {}
  if note.sections then
    for _, section in ipairs(note.sections) do
      if section.header then
        headings[#headings + 1] = {
          anchor = section.anchor,
          header = section.header,
          level = section.level,
          line = section.heading_range.start_row + 1,
          section = section,
        }
      end
    end
  else
    for _, anchor in pairs(note.anchor_links or {}) do
      headings[#headings + 1] = anchor
    end
  end
  return headings
end

---@param cc obsidian.completion.sources.refs.context
---@param query string
---@param results obsidian.Note[]
local function process_heading_search_results(cc, query, results)
  ---@cast cc.insert_start -nil
  ---@cast cc.insert_end -nil
  ---@cast cc.search -nil
  local range = {
    start = { line = cc.request.line, character = cc.insert_start },
    ["end"] = { line = cc.request.line, character = cc.insert_end },
  }
  local source_name = vim.api.nvim_buf_get_name(cc.request.bufnr)
  local source_dir = source_name ~= "" and vim.fs.dirname(source_name) or nil
  local needle = vim.fn.tolower(query)
  local items = {}
  local seen = {}
  local basename_paths = {}

  table.sort(results, function(a, b)
    return tostring(a.path) < tostring(b.path)
  end)

  if Obsidian.opts.link.format == "shortest" then
    for _, note in ipairs(results) do
      local basename = vim.fs.basename(tostring(note.path))
      basename_paths[basename] = basename_paths[basename] or {}
      basename_paths[basename][tostring(note.path)] = true
    end
  end

  for note_idx, note in ipairs(results) do
    local anchors = {}
    for _, anchor in ipairs(note_headings(note)) do
      local key = tostring(note.path) .. ":" .. anchor.line
      local searchable = anchor.header .. " " .. anchor.anchor
      if not seen[key] and (needle == "" or vim.fn.tolower(searchable):find(needle, 1, true)) then
        seen[key] = true
        anchors[#anchors + 1] = anchor
      end
    end
    table.sort(anchors, function(a, b)
      return a.line < b.line
    end)

    for _, anchor in ipairs(anchors) do
      local basename = vim.fs.basename(tostring(note.path))
      local paths = basename_paths[basename]
      local link_format = paths and vim.tbl_count(paths) > 1 and "absolute" or nil
      local link = note:format_link {
        label = note:display_name(),
        anchor = heading_completion_anchor(anchor),
        dir = source_dir,
        format = link_format,
      }
      local label = anchor.header .. " — " .. note:display_name()
      items[#items + 1] = {
        label = label,
        sortText = ("%08d:%08d"):format(note_idx, anchor.line),
        filterText = "[[##" .. query .. " " .. anchor.header .. " " .. note:display_name(),
        documentation = {
          kind = "markdown",
          value = note:display_info { label = link, anchor = anchor },
        },
        kind = vim.lsp.protocol.CompletionItemKind.Reference,
        textEdit = {
          newText = link,
          range = range,
        },
      }
    end
  end

  cc.completion_resolve_callback { isIncomplete = true, items = items }
end

---@param cc obsidian.completion.sources.refs.context
---@param query string
local function process_heading_search(cc, query)
  local source_name = vim.api.nvim_buf_get_name(cc.request.bufnr)
  local dir = api.resolve_workspace_dir(source_name ~= "" and source_name or nil)
  local note_opts = { max_lines = ALL_LINES, collect_sections = true }
  local function finish(results)
    process_heading_search_results(cc, query, include_loaded_notes(results, dir, note_opts, true))
  end

  if cache.is_enabled() and cache.is_ready() then
    finish(cached_heading_notes(query))
  else
    -- Heading queries also match normalized anchors, which cannot be mapped
    -- reliably back to raw file text (e.g. `http-api` vs `HTTP API`). Enumerate
    -- notes first, then filter their parsed headings below.
    search.find_notes_async("", finish, {
      dir = dir,
      search = { sort = false, include_templates = false, ignore_case = true },
      notes = note_opts,
    })
  end
end

--- Determines whatever the in_buffer_only should be enabled
---@param cc obsidian.completion.sources.refs.context
local function determine_buffer_only_search_scope(cc)
  if not cc.search then
    return
  end
  if (cc.anchor_link or cc.block_link) and string.len(cc.search) == 0 then
    -- Search over headers/blocks in current buffer only.
    cc.in_buffer_only = true
  end
end

--- Strips block and anchor links from the current search string
---@param cc obsidian.completion.sources.refs.context
local function strip_links(cc)
  if not cc.search then
    return
  end
  cc.search, cc.block_link = util.strip_block_links(cc.search)
  cc.search, cc.anchor_link = util.strip_anchor_links(cc.search)

  -- If block link is incomplete, we'll match against all block links.
  if not cc.block_link and vim.endswith(cc.search, "#^") then
    cc.block_link = "#^"
    cc.search = string.sub(cc.search, 1, -3)
  end

  -- If anchor link is incomplete, we'll match against all anchor links.
  if not cc.anchor_link and vim.endswith(cc.search, "#") then
    cc.anchor_link = "#"
    cc.search = string.sub(cc.search, 1, -2)
  end
end

---@param cc obsidian.completion.sources.refs.context
---@param label string|?
---@param alt_label string|?
---@param note obsidian.Note
local function update_completion_options(cc, label, alt_label, matching_anchors, matching_blocks, note)
  ---@type { label: string|?, alt_label: string|?, anchor: obsidian.note.HeaderAnchor|?, block: obsidian.note.Block|? }[]
  local new_options = {}
  if matching_anchors ~= nil then
    for _, anchor in ipairs(matching_anchors) do
      table.insert(new_options, { label = label, alt_label = alt_label, anchor = anchor })
    end
  elseif matching_blocks ~= nil then
    for _, block in ipairs(matching_blocks) do
      table.insert(new_options, { label = label, alt_label = alt_label, block = block })
    end
  else
    if label then
      table.insert(new_options, { label = label, alt_label = alt_label })
    end

    -- Add all blocks and anchors, let cmp sort it out.
    for _, anchor_data in pairs(note.anchor_links or {}) do
      table.insert(new_options, { label = label, alt_label = alt_label, anchor = anchor_data })
    end
    for _, block_data in pairs(note.blocks or {}) do
      table.insert(new_options, { label = label, alt_label = alt_label, block = block_data })
    end
  end

  -- De-duplicate options relative to their `new_text`.
  for _, option in ipairs(new_options) do
    local final_label, sort_text, new_text, documentation
    if option.label then
      new_text = note:format_link { label = option.label, anchor = option.anchor, block = option.block }

      final_label = option.alt_label or option.label
      if option.anchor then
        final_label = final_label .. option.anchor.anchor
      elseif option.block then
        final_label = final_label .. "#" .. option.block.id
      end
      sort_text = final_label

      documentation = {
        kind = "markdown",
        value = note:display_info {
          label = new_text,
          anchor = option.anchor,
          block = option.block,
        },
      }
    elseif option.anchor then
      -- In buffer anchor link.
      if Obsidian.opts.link.style == "wiki" then
        new_text = "[[#" .. option.anchor.header .. "]]"
      elseif Obsidian.opts.link.style == "markdown" then
        new_text = "[#" .. option.anchor.header .. "](" .. option.anchor.anchor .. ")"
      elseif type(Obsidian.opts.link.style) == "function" then
        new_text = Obsidian.opts.link.style { label = option.label or "", path = "", anchor = option.anchor }
      else
        error "not implemented"
      end

      final_label = option.anchor.anchor
      sort_text = final_label

      documentation = {
        kind = "markdown",
        value = string.format("`%s`", new_text),
      }
    elseif option.block then
      -- In buffer block link.
      new_text = format_current_block_link(option.block)

      final_label = "#" .. option.block.id
      sort_text = final_label

      documentation = {
        kind = "markdown",
        value = string.format("`%s`", new_text),
      }
    else
      error "should not happen"
    end

    -- use absolute unless relative
    local resolve_link_format = Obsidian.opts.link.format == "relative" and "relative" or "absolute"

    if cc.new_text_to_option[new_text] then
      local existing = cc.new_text_to_option[new_text]
      if
        option.label
        and existing.note
        and existing.note.path
        and tostring(existing.note.path) ~= tostring(note.path)
      then
        -- Different notes produced the same link text: disambiguate using vault-relative paths.
        if not existing.disambiguated then
          cc.new_text_to_option[new_text] = nil
          local ex_new_text = existing.note:format_link {
            label = existing.label,
            format = resolve_link_format,
            anchor = existing.anchor,
            block = existing.block,
          }
          existing.new_text = ex_new_text
          existing.disambiguated = true
          cc.new_text_to_option[ex_new_text] = existing
        end

        local cur_new_text = note:format_link {
          label = final_label,
          format = resolve_link_format,
          anchor = option.anchor,
          block = option.block,
        }
        if not cc.new_text_to_option[cur_new_text] then
          cc.new_text_to_option[cur_new_text] = {
            label = final_label,
            new_text = cur_new_text,
            sort_text = sort_text,
            documentation = documentation,
            note = note,
            disambiguated = true,
          }
        end
      end
    else
      cc.new_text_to_option[new_text] = {
        label = final_label,
        new_text = new_text,
        sort_text = sort_text,
        documentation = documentation,
        note = option.label and note or nil,
        anchor = option.anchor,
        block = option.block,
      }
    end
  end
end

---@param cc obsidian.completion.sources.refs.context
---@param results obsidian.Note[]
local function process_search_results(cc, results)
  if not cc.search then
    return
  end
  local completion_items = {}

  for _, note in ipairs(results) do
    ---@cast note obsidian.Note

    local matching_blocks = completion.collect_matching_blocks(note, cc.block_link)
    local matching_anchors = completion.collect_matching_anchors(note, cc.anchor_link)

    if cc.in_buffer_only then
      update_completion_options(cc, nil, nil, matching_anchors, matching_blocks, note)
    else
      -- Collect all valid aliases for the note, including ID, title, and filename.
      local aliases = util.tbl_unique { tostring(note.id), note:display_name(), unpack(note.aliases) }

      for _, alias in ipairs(aliases) do
        update_completion_options(cc, alias, nil, matching_anchors, matching_blocks, note)
        local alias_case_matched = util.match_case(cc.search, alias)

        if
          alias_case_matched ~= nil
          and alias_case_matched ~= alias
          and not vim.list_contains(note.aliases, alias_case_matched)
          and Obsidian.opts.completion.match_case
        then
          update_completion_options(cc, alias_case_matched, nil, matching_anchors, matching_blocks, note)
        end
      end

      if note.alt_alias ~= nil then
        update_completion_options(cc, note:display_name(), note.alt_alias, matching_anchors, matching_blocks, note)
      end
    end
  end

  for _, option in pairs(cc.new_text_to_option) do
    -- TODO: need a better label, maybe just the note's display name?
    local option_label = option.label or ""
    ---@type string
    local label
    if Obsidian.opts.link.style == "wiki" then
      label = string.format("[[%s]]", option_label)
    elseif Obsidian.opts.link.style == "markdown" then
      label = string.format("[%s](…)", option_label)
    elseif type(Obsidian.opts.link.style) == "function" then
      label = Obsidian.opts.link.style { label = option_label, path = "" }
    else
      error "not implemented"
    end

    table.insert(completion_items, {
      documentation = option.documentation,
      sortText = option.sort_text,
      filterText = completion.get_filter_text(option_label),
      label = label,
      kind = vim.lsp.protocol.CompletionItemKind.Reference,
      textEdit = {
        newText = option.new_text,
        range = {
          ["start"] = {
            line = cc.request.line,
            character = cc.insert_start,
          },
          ["end"] = {
            line = cc.request.line,
            character = cc.insert_end,
          },
        },
      },
    })
  end

  cc.completion_resolve_callback {
    isIncomplete = true,
    items = completion_items,
  }
end

---@param completion_resolve_callback function
---@param request obsidian.completion.Request
function M.process_completion(completion_resolve_callback, request)
  local cc = {
    completion_resolve_callback = completion_resolve_callback,
    request = request,
    in_buffer_only = false,
    new_text_to_option = {},
  }

  if not can_complete_request(cc) or not cc.search then
    cc.completion_resolve_callback(EMPTY_RESPONSE)
    return
  end

  local heading_query = completion.heading_search(cc.search)
  if heading_query ~= nil then
    process_heading_search(cc, heading_query)
    return
  end

  local block_scope, block_query, block_target = completion.block_search(cc.search)
  if block_scope and block_query then
    process_block_search(cc, block_scope, block_query, block_target)
    return
  end

  strip_links(cc)
  determine_buffer_only_search_scope(cc)

  if cc.in_buffer_only then
    local note = api.current_note(cc.request.bufnr, { collect_anchor_links = true, collect_blocks = true })
    if note then
      process_search_results(cc, { note })
    else
      cc.completion_resolve_callback(EMPTY_RESPONSE)
    end
  else
    local search_opts = {
      sort = false,
      include_templates = false,
      ignore_case = true,
    }

    local source_path = vim.api.nvim_buf_get_name(cc.request.bufnr)
    search.find_notes_async(cc.search, function(results)
      process_search_results(cc, results)
    end, {
      dir = api.resolve_workspace_dir(source_path),
      search = search_opts,
      notes = { collect_anchor_links = cc.anchor_link ~= nil, collect_blocks = cc.block_link ~= nil },
    })
  end
end

return M
