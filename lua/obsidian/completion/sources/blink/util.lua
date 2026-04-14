local M = {}

---Generates the completion request from a blink context.
---
---blink.cmp gets cursor from nvim_win_get_cursor (byte offset) and applies
---textEdits via vim.lsp.util.apply_text_edits with 'utf-8' encoding, so all
---positions are in bytes. We use byte offsets throughout to stay consistent.
---@param context blink.cmp.Context
---@return obsidian.completion.sources.base.Request
M.generate_completion_request_from_editor_state = function(context)
  local row = context.cursor[1]
  -- context.cursor[2] is a 0-indexed byte offset from nvim_win_get_cursor
  local byte_col = context.cursor[2]
  local cursor_before_line = context.line:sub(1, byte_col)
  local cursor_after_line = context.line:sub(byte_col + 1)

  return {
    context = {
      bufnr = context.bufnr,
      cursor_before_line = cursor_before_line,
      cursor_after_line = cursor_after_line,
      cursor = {
        row = row,
        line = row,
        character = byte_col,
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
