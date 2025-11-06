local TagsSourceBase = require "obsidian.completion.sources.base.tags"
local completion = require "obsidian.completion.tags"
local nvim_cmp_util = require "obsidian.completion.sources.nvim_cmp.util"

---@class obsidian.completion.sources.nvim_cmp.TagsSource : obsidian.completion.sources.base.TagsSourceBase
local TagsSource = {}
TagsSource.__index = TagsSource

TagsSource.new = function()
  return setmetatable(TagsSourceBase, TagsSource)
end

TagsSource.get_keyword_pattern = completion.get_keyword_pattern

TagsSource.incomplete_response = nvim_cmp_util.incomplete_response
TagsSource.complete_response = nvim_cmp_util.complete_response

function TagsSource:complete(request, callback)
  local cc = self:new_completion_context(callback, request)
  self:process_completion(cc)
end

return TagsSource
