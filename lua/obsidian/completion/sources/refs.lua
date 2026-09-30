--- TODO: make more declarative
local completion = require "obsidian.completion.refs"
local util = require "obsidian.util"
local fs_util = require "obsidian.util.fs"
local compat = require "obsidian.compat"
local link_parser = require "obsidian.link.parser"
local header_parser = require "obsidian.parse.header"
local block_ids = require "obsidian.parse.block_id"
local api = require "obsidian.api"
local search = require "obsidian.search"
local cache = require "obsidian.cache"

---@class obsidian.completion.sources.refs.options
---@field label string|?
---@field display_label string|?
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

---@type table<string, table>
local block_search_pending = {}

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

---@param text string
---@return string
local function block_label(text)
  local label = text:gsub("%s+", " ")
  if vim.fn.strchars(label) > 80 then
    label = vim.fn.strcharpart(label, 0, 79) .. "…"
  end
  return label
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

---Use the headings' original spelling in wiki-link completion while retaining
---nested anchor paths when the selected anchor includes them.
---@param anchor obsidian.note.HeaderAnchor|?
---@return obsidian.note.HeaderAnchor|?
local function wiki_completion_anchor(anchor)
  if not anchor or Obsidian.opts.link.style ~= "wiki" then
    return anchor
  end

  local headers = { anchor.header }
  if anchor.anchor:find("#", 2, true) then
    local parent = anchor.parent
    while parent do
      table.insert(headers, 1, parent.header)
      parent = parent.parent
    end
  end

  -- These characters are parsed as wiki-link syntax rather than heading text.
  -- Keep the normalized anchor when the original spelling cannot be represented safely.
  for _, header in ipairs(headers) do
    if header:find "[|%[%]]" or vim.startswith(header, "^") then
      return anchor
    end
  end

  local formatted = vim.tbl_extend("force", anchor, { anchor = "#" .. table.concat(headers, "#") })
  ---@cast formatted obsidian.note.HeaderAnchor
  return formatted
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
---@param parse_opts obsidian.note.LoadOpts
---@param include_unmatched boolean|?
---@return obsidian.Note[]
local function include_loaded_notes(results, dir, parse_opts, include_unmatched)
  local path_to_idx = {}
  for idx, note in ipairs(results) do
    path_to_idx[tostring(note.path)] = idx
  end

  local Note = require "obsidian.note"
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local path = vim.uv.fs_realpath(vim.fn.resolve(vim.api.nvim_buf_get_name(bufnr)))
      path = path and vim.fs.normalize(path)
      if path and fs_util.is_subpath(path, tostring(dir)) and api.path_is_note(path) then
        local idx = path_to_idx[path]
        if not idx or vim.bo[bufnr].modified then
          local note = Note.from_buffer(bufnr, parse_opts)
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
---@param matches obsidian.search.BlockSearchMatch[]
local function process_block_search_results(cc, scope, matches)
  local range, placeholder = block_completion_request_context(cc)
  local items = {}
  for _, match in ipairs(matches) do
    local link = scope == "current" and format_current_block_link(match.block)
      or match.note:format_link { label = match.note:display_name(), block = match.block }
    ---@type string
    local label = block_label(match.text)
    if match.existing then
      label = label .. " " .. match.block.id
    end
    if scope == "vault" then
      label = label .. " — " .. match.note:display_name()
    end

    local new_target
    if not match.existing then
      new_target = {
        path = match.path,
        bufnr = match.bufnr,
        range = {
          start = { line = match.section.range.start_row, character = 0 },
          ["end"] = { line = match.section.range.end_row, character = 0 },
        },
        checksum = match.checksum,
        placement = assert(match.placement, "generated block placement is missing"),
        indent = match.indent,
      }
    end
    items[#items + 1] = make_block_completion_item(cc, range, placeholder, {
      note = match.note,
      block = match.block,
      label = label,
      sort_text = ("%08d:%08d"):format(match.note_index, match.section.range.start_row),
      link = link,
      new_target = new_target,
    })
  end
  cc.completion_resolve_callback { isIncomplete = true, items = items }
end

---@param cc obsidian.completion.sources.refs.context
---@return string
local function block_request_key(cc)
  return ("%d:%d:%d"):format(
    cc.request.bufnr,
    cc.request.line,
    assert(cc.insert_start, "block completion insert start is missing")
  )
end

---@param cc obsidian.completion.sources.refs.context
local function cancel_block_request(cc)
  local key = block_request_key(cc)
  local pending = block_search_pending[key]
  if pending then
    block_search_pending[key] = nil
    pending.cc.completion_resolve_callback(EMPTY_RESPONSE)
  end
end

---@param cc obsidian.completion.sources.refs.context
---@param scope "current"|"note"|"vault"
---@param query string
---@param target string|?
local function process_block_search(cc, scope, query, target)
  local should_complete = vim.fn.strchars(query) >= Obsidian.opts.completion.min_chars
  local dir = api.resolve_workspace_dir()
  local _, _, source_path = block_completion_request_context(cc)

  if not should_complete then
    cancel_block_request(cc)
    cc.completion_resolve_callback(EMPTY_RESPONSE)
    if scope == "vault" then
      search.find_blocks_async("", function() end, { dir = dir })
    end
    return
  end

  local key = block_request_key(cc)
  cancel_block_request(cc)
  local request = { cc = cc }
  block_search_pending[key] = request

  local function finish(matches)
    if block_search_pending[key] ~= request then
      return
    end
    block_search_pending[key] = nil
    process_block_search_results(cc, scope, matches)
  end

  local function search_notes(notes)
    if block_search_pending[key] ~= request then
      return
    end
    search.find_blocks_async(query, finish, {
      note_list = notes,
      source_path = source_path,
      source_row = cc.request.line,
    })
  end

  if scope == "current" then
    local note = api.current_note(cc.request.bufnr, {
      collect_blocks = true,
      collect_block_candidates = true,
    })
    search_notes(note and { note } or {})
  elseif scope == "note" then
    search.resolve_note_async(assert(target, "named-note block search requires a target"), search_notes, {
      collect = { blocks = true },
    })
  else
    search.find_blocks_async(query, finish, {
      dir = dir,
      source_path = source_path,
      source_row = cc.request.line,
    })
  end
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
        local created = Note.from_cache(heading.path, row)
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
  local parse_opts = { collect_sections = true }
  local function finish(results)
    process_heading_search_results(cc, query, include_loaded_notes(results, dir, parse_opts, true))
  end

  if cache.is_enabled() and cache.is_ready() then
    finish(cached_heading_notes(query))
  else
    -- Heading queries also match normalized anchors, which cannot be mapped
    -- reliably back to raw file text (e.g. `http-api` vs `HTTP API`). Enumerate
    -- notes first, then filter their parsed headings below.
    search.find_notes_async("", finish, {
      dir = dir,
      sort_by = false,
      match = { headings = true },
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
  local anchor, block
  cc.search, anchor, block = link_parser.parse(cc.search)
  cc.block_link = block ~= nil and "#" .. block_ids.normalize(block) or nil
  cc.anchor_link = anchor ~= nil and header_parser.normalize_anchor(anchor) or nil
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
    local final_label, display_label, sort_text, new_text, documentation
    local formatted_anchor = wiki_completion_anchor(option.anchor)
    if option.label then
      new_text = note:format_link { label = option.label, anchor = formatted_anchor, block = option.block }

      final_label = option.alt_label or option.label
      display_label = final_label
      if option.anchor then
        final_label = final_label .. option.anchor.anchor
        local display_anchor = assert(formatted_anchor, "formatted heading anchor is required")
        display_label = display_label
          .. (Obsidian.opts.link.style == "wiki" and display_anchor.anchor or "#" .. option.anchor.header)
      elseif option.block then
        final_label = final_label .. "#" .. option.block.id
        display_label = final_label
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
      display_label = "#" .. option.anchor.header
      sort_text = final_label

      documentation = {
        kind = "markdown",
        value = string.format("`%s`", new_text),
      }
    elseif option.block then
      -- In buffer block link.
      new_text = format_current_block_link(option.block)

      final_label = "#" .. option.block.id
      display_label = final_label
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
          anchor = formatted_anchor,
          block = option.block,
        }
        if not cc.new_text_to_option[cur_new_text] then
          cc.new_text_to_option[cur_new_text] = {
            label = final_label,
            display_label = display_label,
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
        display_label = display_label,
        new_text = new_text,
        sort_text = sort_text,
        documentation = documentation,
        note = option.label and note or nil,
        anchor = formatted_anchor,
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
      -- Collect all valid aliases for the note, including ID, title, aliases, and filename stem.
      local aliases = { tostring(note.id), note:display_name() }
      if note.path then
        aliases[#aliases + 1] = note.path.stem
      end
      vim.list_extend(aliases, note.aliases)
      compat.list_unique(aliases)

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
    local option_label = option.display_label or option.label or ""
    local filter_label = option.label or option_label
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
      filterText = completion.get_filter_text(filter_label),
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

---Use cached metadata to return the complete ordinary note-reference candidate set.
---Completion clients can then apply their own fuzzy matcher without a filesystem search.
---@param cc obsidian.completion.sources.refs.context
---@return boolean handled
local function process_cached_search(cc)
  if not cache.is_enabled() or not cache.is_ready() or cc.anchor_link ~= nil or cc.block_link ~= nil then
    return false
  end

  local source_path = vim.api.nvim_buf_get_name(cc.request.bufnr)
  local dir = api.resolve_workspace_dir(source_path ~= "" and source_path or nil)
  local workspace = api.find_workspace(dir)
  local templates_dir = api.templates_dir(workspace)
  local rows = cache.notes.all()
  local paths = {}

  for path in pairs(rows) do
    if
      fs_util.is_subpath(path, tostring(dir))
      and (not templates_dir or not fs_util.is_subpath(path, tostring(templates_dir)))
    then
      paths[#paths + 1] = path
    end
  end
  table.sort(paths)

  local Note = require "obsidian.note"
  ---@type obsidian.Note[]
  local notes = {}
  for _, path in ipairs(paths) do
    notes[#notes + 1] = Note.from_cache(path, rows[path])
  end

  process_search_results(cc, include_loaded_notes(notes, dir, {}, true))
  return true
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
    if process_cached_search(cc) then
      return
    end

    local source_path = vim.api.nvim_buf_get_name(cc.request.bufnr)
    search.find_notes_async(cc.search, function(results)
      process_search_results(cc, results)
    end, {
      dir = api.resolve_workspace_dir(source_path),
      sort_by = false,
      collect = { headings = cc.anchor_link ~= nil, blocks = cc.block_link ~= nil },
    })
  end
end

return M
