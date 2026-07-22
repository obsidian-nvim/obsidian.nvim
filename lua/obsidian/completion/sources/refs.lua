local completion = require "obsidian.completion.refs"
local fragments = require "obsidian.completion.fragments"
local util = require "obsidian.util"
local api = require "obsidian.api"
local search = require "obsidian.search"

---@class obsidian.completion.sources.refs.options
---@field label string
---@field link_label string
---@field new_text string
---@field sort_text string
---@field documentation table
---@field note obsidian.Note
---@field disambiguated boolean|?

local M = {}

local EMPTY_RESPONSE = {
  isIncomplete = true,
  items = {},
}

---@param note obsidian.Note
---@param link_label string
---@param label string|?
---@return obsidian.completion.sources.refs.options
local function make_option(note, link_label, label)
  local final_label = label or link_label
  local new_text = note:format_link { label = link_label }
  return {
    label = final_label,
    link_label = link_label,
    new_text = new_text,
    sort_text = final_label,
    documentation = {
      kind = "markdown",
      value = note:display_info { label = new_text },
    },
    note = note,
  }
end

---@param options table<string, obsidian.completion.sources.refs.options>
---@param option obsidian.completion.sources.refs.options
local function add_option(options, option)
  local existing = options[option.new_text]
  if not existing then
    options[option.new_text] = option
    return
  elseif tostring(existing.note.path) == tostring(option.note.path) then
    return
  end

  -- Two notes produced the same shortest link. Use a path for both so accepting
  -- either item remains unambiguous.
  local format = Obsidian.opts.link.format == "relative" and "relative" or "absolute"
  if not existing.disambiguated then
    options[existing.new_text] = nil
    existing.new_text = existing.note:format_link { label = existing.link_label, format = format }
    existing.disambiguated = true
    options[existing.new_text] = existing
  end

  option.new_text = option.note:format_link { label = option.link_label, format = format }
  option.disambiguated = true
  if not options[option.new_text] then
    options[option.new_text] = option
  end
end

---@param callback fun(resp: lsp.CompletionList)
---@param request obsidian.completion.Request
function M.process_completion(callback, request)
  local can_complete, term, insert_start, insert_end = completion.can_complete(request)
  if not (can_complete and term and #term >= Obsidian.opts.completion.min_chars) then
    callback(EMPTY_RESPONSE)
    return
  end

  ---@cast insert_start -nil
  ---@cast insert_end -nil

  search.find_notes_async(term, function(results)
    local options = {}

    for _, note in ipairs(results) do
      local aliases = util.tbl_unique { tostring(note.id), note:display_name(), unpack(note.aliases) }
      for _, alias in ipairs(aliases) do
        add_option(options, make_option(note, alias))

        local case_matched = util.match_case(term, alias)
        if
          case_matched ~= nil
          and case_matched ~= alias
          and not vim.list_contains(note.aliases, case_matched)
          and Obsidian.opts.completion.match_case
        then
          add_option(options, make_option(note, case_matched))
        end
      end

      if note.alt_alias ~= nil then
        add_option(options, make_option(note, note:display_name(), note.alt_alias))
      end
    end

    local items = {}
    for _, option in pairs(options) do
      local label
      if Obsidian.opts.link.style == "wiki" then
        label = string.format("[[%s]]", option.label)
      elseif Obsidian.opts.link.style == "markdown" then
        label = string.format("[%s](…)", option.label)
      elseif type(Obsidian.opts.link.style) == "function" then
        label = Obsidian.opts.link.style { label = option.label, path = "" }
      else
        error "not implemented"
      end

      local new_text = option.new_text
      local snippet = fragments.chainable_snippet(new_text)
      local item = {
        documentation = option.documentation,
        sortText = option.sort_text,
        filterText = completion.get_filter_text(option.label),
        label = label,
        kind = vim.lsp.protocol.CompletionItemKind.Reference,
        textEdit = {
          newText = snippet or new_text,
          range = {
            start = { line = request.line, character = insert_start },
            ["end"] = { line = request.line, character = insert_end },
          },
        },
      }

      if snippet then
        item.insertTextFormat = vim.lsp.protocol.InsertTextFormat.Snippet
        item.commitCharacters = { "#" }
      end
      items[#items + 1] = item
    end

    callback { isIncomplete = true, items = items }
  end, {
    dir = api.resolve_workspace_dir(),
    search = {
      sort = false,
      include_templates = false,
      ignore_case = true,
    },
  })
end

return M
