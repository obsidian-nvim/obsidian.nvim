local NewNoteSourceBase = require "obsidian.completion.sources.base.new"
local abc = require "obsidian.abc"
local blink_util = require "obsidian.completion.sources.blink.util"

---@class obsidian.completion.sources.blink.NewNoteSource : obsidian.completion.sources.base.NewNoteSourceBase
local NewNoteSource = abc.new_class()

NewNoteSource.incomplete_response = blink_util.incomplete_response
NewNoteSource.complete_response = blink_util.complete_response

function NewNoteSource.new()
  return NewNoteSource.init(NewNoteSourceBase)
end

---Implement the get_completions method of the completion provider
---@param context blink.cmp.Context
---@param resolve fun(self: blink.cmp.CompletionResponse): nil
function NewNoteSource:get_completions(context, resolve)
  local request = blink_util.generate_completion_request_from_editor_state(context)
  local cc = self:new_completion_context(resolve, request)
  self:process_completion(cc)
end

---Implements the execute method of the completion provider
---@param _ blink.cmp.Context
---@param item blink.cmp.CompletionItem
---@param callback fun(),
---@param default_implementation fun(context?: blink.cmp.Context, item?: blink.cmp.CompletionItem)): ((fun(): nil) | nil)
function NewNoteSource:execute(_, item, callback, default_implementation)
  self:process_execute(item)
  default_implementation() -- Ensure completion is still executed
  callback() -- Required (as per blink documentation)
end

return NewNoteSource
