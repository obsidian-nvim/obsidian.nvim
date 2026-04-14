local completion = require "obsidian.completion.tags"
local search = require "obsidian.search"
local api = require "obsidian.api"

---Used to track variables that are used between reusable method calls. This is required, because each
---call to the sources's completion hook won't create a new source object, but will reuse the same one.
---@class obsidian.completion.TagsSourceCompletionContext
---@field completion_resolve_callback fun(resp: lsp.CompletionList)
---@field request obsidian.completion.Request
---@field search string|?
---@field in_frontmatter boolean|?

---@class obsidian.completion.sources.base.TagsSourceBase
---@field incomplete_response table
---@field complete_response table
local M = {
  incomplete_response = { isIncomplete = true },
  complete_response = { isIncomplete = true, items = {} },
}

--- Returns whatever it's possible to complete the search and sets up the search related variables in cc
---@param cc obsidian.completion.TagsSourceCompletionContext
---@return boolean success provides a chance to return early if the request didn't meet the requirements
local function can_complete_request(cc)
  local can_complete
  can_complete, cc.search, cc.in_frontmatter = completion.can_complete(cc.request)

  if not (can_complete and cc.search ~= nil and #cc.search >= Obsidian.opts.completion.min_chars) then
    return false
  end

  return true
end

--- Runs a generalized version of the complete (nvim_cmp) or get_completions (blink) methods
---@param completion_resolve_callback fun(resp: lsp.CompletionList)
---@param request obsidian.completion.Request
function M.process_completion(completion_resolve_callback, request)
  local cc = {
    completion_resolve_callback = completion_resolve_callback,
    request = request,
  }

  if not can_complete_request(cc) then
    cc.completion_resolve_callback(M.incomplete_response)
    return
  end

  search.find_tags_async(cc.search, function(tag_locs)
    local tags = {}
    for tag_loc in vim.iter(tag_locs) do
      tags[tag_loc.tag] = true
    end

    local items = {}
    for tag, _ in pairs(tags) do
      -- Generate context-appropriate text
      local insert_text, label_text
      if cc.in_frontmatter then
        -- Frontmatter: insert tag without # (YAML format)
        insert_text = tag
        label_text = "Tag: " .. tag
      else
        -- Document body: insert tag with # (Obsidian format)
        insert_text = "#" .. tag
        label_text = "Tag: #" .. tag
      end

      -- Calculate the range to replace (the entire #tag pattern)
      local cursor_before = cc.request.cursor_before_line
      local hash_start = string.find(cursor_before, "#[^%s]*$")
      local insert_start = hash_start and (hash_start - 1) or #cursor_before
      local insert_end = #cursor_before

      items[#items + 1] = {
        sortText = "#" .. tag,
        label = label_text,
        kind = vim.lsp.protocol.CompletionItemKind.Text,
        textEdit = {
          newText = insert_text,
          range = {
            ["start"] = {
              line = cc.request.line,
              character = insert_start,
            },
            ["end"] = {
              line = cc.request.line,
              character = insert_end,
            },
          },
        },
      }
    end

    cc.completion_resolve_callback(vim.tbl_deep_extend("force", M.complete_response, { items = items }))
  end, { dir = api.resolve_workspace_dir() })
end

return M
