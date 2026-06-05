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

--- Returns whether it's possible to complete the search and sets up the search related variables in cc
---@param cc obsidian.completion.sources.refs.context
---@return boolean success provides a chance to return early if the request didn't meet the requirements
local function can_complete_request(cc)
  local can_complete
  can_complete, cc.search, cc.insert_start, cc.insert_end = completion.can_complete(cc.request)

  if not (can_complete and cc.search ~= nil and #cc.search >= Obsidian.opts.completion.min_chars) then
    return false
  end

  return true
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
      if Obsidian.opts.link.style == "wiki" then
        new_text = "[[#" .. option.block.id .. "]]"
      elseif Obsidian.opts.link.style == "markdown" then
        new_text = "[#" .. option.block.id .. "](#" .. option.block.id .. ")"
      elseif type(Obsidian.opts.link.style) == "function" then
        new_text = Obsidian.opts.link.style { label = option.label or "", path = "", block = option.block }
      else
        error "not implemented"
      end

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

---@param target string
---@return string new_text
---@return string label
local function format_unresolved_link(target)
  if Obsidian.opts.link.style == "wiki" then
    return string.format("[[%s]]", target), string.format("[[%s]]", target)
  elseif Obsidian.opts.link.style == "markdown" then
    return string.format("[%s](%s)", target, target), string.format("[%s](…)", target)
  elseif type(Obsidian.opts.link.style) == "function" then
    local new_text = Obsidian.opts.link.style { label = target, path = target }
    return new_text, new_text
  else
    error "not implemented"
  end
end

---@param cc obsidian.completion.sources.refs.context
---@param targets string[]
local function update_unresolved_completion_options(cc, targets)
  for _, target in ipairs(targets) do
    local new_text = format_unresolved_link(target)
    if not cc.new_text_to_option[new_text] then
      cc.new_text_to_option[new_text] = {
        label = target,
        new_text = new_text,
        sort_text = target,
        documentation = {
          kind = "markdown",
          value = string.format("Unresolved link: `%s`", new_text),
        },
      }
    end
  end
end

---@param cc obsidian.completion.sources.refs.context
---@param results obsidian.Note[]
---@param unresolved_targets string[]|?
local function process_search_results(cc, results, unresolved_targets)
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

  update_unresolved_completion_options(cc, unresolved_targets or {})

  for _, option in pairs(cc.new_text_to_option) do
    -- TODO: need a better label, maybe just the note's display name?
    ---@type string
    local label
    if Obsidian.opts.link.style == "wiki" then
      label = string.format("[[%s]]", option.label)
    elseif Obsidian.opts.link.style == "markdown" then
      label = string.format("[%s](…)", option.label)
    elseif type(Obsidian.opts.link.style) == "function" then
      label = Obsidian.opts.link.style { label = option.label or "", path = "" }
    else
      error "not implemented"
    end

    table.insert(completion_items, {
      documentation = option.documentation,
      sortText = option.sort_text,
      filterText = completion.get_filter_text(option.label),
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

    local dir = api.resolve_workspace_dir()
    search.find_notes_async(cc.search, function(results)
      search.find_link_targets_async(cc.search, function(link_targets)
        process_search_results(cc, results, link_targets)
      end, {
        dir = dir,
        search = search_opts,
      })
    end, {
      dir = dir,
      search = search_opts,
      notes = { collect_anchor_links = cc.anchor_link ~= nil, collect_blocks = cc.block_link ~= nil },
    })
  end
end

return M
