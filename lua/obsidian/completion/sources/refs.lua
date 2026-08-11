--- TODO: make more declarative
local completion = require "obsidian.completion.refs"
local util = require "obsidian.util"
local api = require "obsidian.api"
local search = require "obsidian.search"

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
      and (completion.block_search(cc.search) ~= nil or #cc.search >= Obsidian.opts.completion.min_chars)
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

---@param results obsidian.Note[]
---@param dir obsidian.Path
---@param include_unmatched boolean|?
---@return obsidian.Note[]
local function include_loaded_notes(results, dir, include_unmatched)
  local path_to_idx = {}
  for idx, note in ipairs(results) do
    path_to_idx[tostring(note.path)] = idx
  end

  local Note = require "obsidian.note"
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local path = vim.uv.fs_realpath(vim.fn.resolve(vim.api.nvim_buf_get_name(bufnr)))
      if path and util.is_subpath(path, tostring(dir)) and api.path_is_note(path) then
        local note = Note.from_buffer(bufnr, {
          max_lines = vim.api.nvim_buf_line_count(bufnr),
          collect_blocks = true,
          collect_block_candidates = true,
        })
        local idx = path_to_idx[tostring(note.path)]
        if idx then
          results[idx] = note
        elseif include_unmatched ~= false then
          results[#results + 1] = note
          path_to_idx[tostring(note.path)] = #results
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
  ---@cast cc.insert_start -nil
  ---@cast cc.insert_end -nil
  ---@type lsp.Range
  local range = {
    start = { line = cc.request.line, character = cc.insert_start },
    ["end"] = { line = cc.request.line, character = cc.insert_end },
  }
  local placeholder = current_completion_text(cc.request, range)
  local source_name = vim.api.nvim_buf_get_name(cc.request.bufnr)
  local source_path = vim.uv.fs_realpath(vim.fn.resolve(source_name)) or vim.fs.normalize(source_name)
  local lowered_query = vim.fn.tolower(query)
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

          local item = {
            label = label,
            sortText = ("%08d:%08d"):format(note_idx, section.range.start_row),
            filterText = (scope == "vault" and "[[^^" or "[[^") .. query .. " " .. label,
            documentation = {
              kind = "markdown",
              value = note:display_info { label = link, block = block },
            },
            kind = vim.lsp.protocol.CompletionItemKind.Reference,
            textEdit = {
              newText = existing and link or placeholder,
              range = range,
            },
          }

          if not existing then
            local placement, indent = block_id_placement(lines, section)
            item.command = {
              command = "obsidian.block_reference_new",
              title = "Obsidian create block reference",
              arguments = {
                {
                  target_path = tostring(note.path),
                  target_bufnr = note.bufnr,
                  target_range = {
                    start = { line = section.range.start_row, character = 0 },
                    ["end"] = { line = section.range.end_row, character = 0 },
                  },
                  target_checksum = vim.fn.sha256(table.concat(note.contents, "\n")),
                  block_id = block.id,
                  placement = placement,
                  indent = indent,
                  source_bufnr = cc.request.bufnr,
                  source_range = range,
                  source_text = link,
                  placeholder = placeholder,
                },
              },
            }
          end
          items[#items + 1] = item
        end
      end
    end
  end

  cc.completion_resolve_callback { isIncomplete = true, items = items }
end

---@param cc obsidian.completion.sources.refs.context
---@param scope "current"|"note"|"vault"
---@param query string
---@param target string|?
local function process_block_search(cc, scope, query, target)
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
    process_block_search_results(cc, scope, query, include_loaded_notes(results, dir, scope == "vault"))
  end
  if scope == "note" then
    search.resolve_note_async(
      assert(target, "named-note block search requires a target"),
      on_results,
      { notes = note_opts }
    )
    return
  end
  search.find_notes_async(query, on_results, {
    dir = dir,
    search = { sort = false, include_templates = false, ignore_case = true },
    notes = note_opts,
  })
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

  local block_scope, block_query, block_target = completion.block_search(cc.search)
  if block_scope and block_query then
    process_block_search(cc, block_scope, block_query, block_target)
    return
  end

  strip_links(cc)
  determine_buffer_only_search_scope(cc)

  if cc.in_buffer_only then
    local note = api.current_note(0, { collect_anchor_links = true, collect_blocks = true })
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

    search.find_notes_async(cc.search, function(results)
      process_search_results(cc, results)
    end, {
      dir = api.resolve_workspace_dir(),
      search = search_opts,
      notes = { collect_anchor_links = cc.anchor_link ~= nil, collect_blocks = cc.block_link ~= nil },
    })
  end
end

return M
