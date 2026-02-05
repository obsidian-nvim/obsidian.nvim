local M = {}

---Safe version of vim.str_utfindex
---@param text string
---@param vimindex integer|nil
---@return integer
local to_utfindex = function(text, vimindex)
  vimindex = vimindex or #text + 1
  if vim.fn.has "nvim-0.11" == 1 then
    return vim.str_utfindex(text, "utf-8", math.max(0, math.min(vimindex - 1, #text)))
  end
  return vim.str_utfindex(text, math.max(0, math.min(vimindex - 1, #text)))
end

---Generates the completion request from a blink context
---@param context blink.cmp.Context
---@return obsidian.completion.sources.base.Request
M.generate_completion_request_from_editor_state = function(context)
  local row = context.cursor[1]
  local col = context.cursor[2] + 1
  local cursor_before_line = context.line:sub(1, col - 1)
  local cursor_after_line = context.line:sub(col)

  local character = to_utfindex(context.line, col)

  return {
    context = {
      bufnr = context.bufnr,
      cursor_before_line = cursor_before_line,
      cursor_after_line = cursor_after_line,
      cursor = {
        row = row,
        col = col,
        line = row + 1,
        character = character,
      },
    },
  }
end

M.incomplete_response = {
  is_incomplete_forward = true,
  is_incomplete_backward = true,
  items = {},
}

M.complete_response = {
  is_incomplete_forward = true,
  is_incomplete_backward = false,
  items = {},
}

return M
