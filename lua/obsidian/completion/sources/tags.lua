local completion = require "obsidian.completion.tags"
local search = require "obsidian.search"
local api = require "obsidian.api"

local M = {}

---@type lsp.CompletionList
local EMPTY_RESPONSE = {
  isIncomplete = true,
  items = {},
}

--- Runs a generalized version of the complete (nvim_cmp) or get_completions (blink) methods
---@param callback fun(resp: lsp.CompletionList)
---@param request obsidian.completion.Request
function M.process_completion(callback, request)
  local can_complete, term = completion.can_complete(request)

  if not (can_complete and term ~= nil and #term >= Obsidian.opts.completion.min_chars) then
    callback(EMPTY_RESPONSE)
    return
  end

  ---@cast term -nil

  search.find_tags_async(term, function(tag_locs)
    local tags = {}
    for _, tag_loc in ipairs(tag_locs) do
      tags[tag_loc.tag] = (tags[tag_loc.tag] or 0) + 1
    end

    local items = {}
    for tag, count in pairs(tags) do
      -- Calculate the range to replace (the entire #tag pattern).
      local cursor_before = request.cursor_before_line
      local hash_start = assert(string.find(cursor_before, "#[^%s]*$"))
      local insert_start = hash_start - 1
      local insert_end = #cursor_before

      items[#items + 1] = {
        sortText = tag,
        filterText = "#" .. tag,
        label = "Tag: #" .. tag,
        kind = vim.lsp.protocol.CompletionItemKind.Keyword,
        documentation = {
          kind = "markdown",
          value = string.format("`#%s` — %d occurrence%s", tag, count, count == 1 and "" or "s"),
        },
        textEdit = {
          newText = "#" .. tag,
          range = {
            ["start"] = {
              line = request.line,
              character = insert_start,
            },
            ["end"] = {
              line = request.line,
              character = insert_end,
            },
          },
        },
      }
    end

    callback {
      isIncomplete = true,
      items = items,
    }
  end, { dir = api.resolve_workspace_dir() })
end

return M
