local completion = require "obsidian.completion.tags"
local iter = vim.iter
local search = require "obsidian.search"
local api = require "obsidian.api"

---Used to track variables that are used between reusable method calls. This is required, because each
---call to the sources's completion hook won't create a new source object, but will reuse the same one.
---@class obsidian.completion.sources.base.TagsSourceCompletionContext
---@field completion_resolve_callback (fun(self: any)) blink or nvim_cmp completion resolve callback
---@field request obsidian.completion.sources.base.Request
---@field search string|?
---@field in_frontmatter boolean|?
---@field workspace obsidian.Workspace
local TagsSourceCompletionContext = {}
TagsSourceCompletionContext.__index = TagsSourceCompletionContext

TagsSourceCompletionContext.new = function()
  return setmetatable({}, TagsSourceCompletionContext)
end

---@class obsidian.completion.sources.base.TagsSourceBase
---@field incomplete_response table
---@field complete_response table
local TagsSourceBase = {}
TagsSourceBase.__index = TagsSourceBase

---@return obsidian.completion.sources.base.TagsSourceBase
TagsSourceBase.new = function()
  return setmetatable({}, TagsSourceBase)
end

TagsSourceBase.get_trigger_characters = completion.get_trigger_characters

---Sets up a new completion context that is used to pass around variables between completion source methods
---@param completion_resolve_callback (fun(self: any)) blink or nvim_cmp completion resolve callback
---@param request obsidian.completion.sources.base.Request
---@return obsidian.completion.sources.base.TagsSourceCompletionContext
function TagsSourceBase:new_completion_context(completion_resolve_callback, request)
  local completion_context = TagsSourceCompletionContext.new()

  -- Sets up the completion callback, which will be called when the (possibly incomplete) completion items are ready
  completion_context.completion_resolve_callback = completion_resolve_callback

  -- This request object will be used to determine the current cursor location and the text around it
  completion_context.request = request

  completion_context.workspace = api.find_workspace(vim.api.nvim_buf_get_name(0))

  return completion_context
end

--- Runs a generalized version of the complete (nvim_cmp) or get_completions (blink) methods
---@param cc obsidian.completion.sources.base.TagsSourceCompletionContext
function TagsSourceBase:process_completion(cc)
  if not self:can_complete_request(cc) then
    return
  end

  search.find_tags_async(cc.search, function(tag_locs)
    local tags = {}
    for tag_loc in iter(tag_locs) do
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
      local cursor_before = cc.request.context.cursor_before_line
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
              line = cc.request.context.cursor.row - 1,
              character = insert_start,
            },
            ["end"] = {
              line = cc.request.context.cursor.row - 1,
              character = insert_end,
            },
          },
        },
        data = {
          bufnr = cc.request.context.bufnr,
          in_frontmatter = cc.in_frontmatter,
          line = cc.request.context.cursor.line,
          tag = tag,
        },
      }
    end

    cc.completion_resolve_callback(vim.tbl_deep_extend("force", self.complete_response, { items = items }))
  end, { dir = cc.workspace.root })
end

--- Returns whatever it's possible to complete the search and sets up the search related variables in cc
---@param cc obsidian.completion.sources.base.TagsSourceCompletionContext
---@return boolean success provides a chance to return early if the request didn't meet the requirements
function TagsSourceBase:can_complete_request(cc)
  local can_complete
  can_complete, cc.search, cc.in_frontmatter = completion.can_complete(cc.request)

  if not (can_complete and cc.search ~= nil and #cc.search >= Obsidian.opts.completion.min_chars) then
    cc.completion_resolve_callback(self.incomplete_response)
    return false
  end

  return true
end

return TagsSourceBase
