local set_checkbox = require("obsidian.api").set_checkbox

---@param data CommandArgs
return function(_, data)
  local start_line, end_line, state
  start_line = data.line1
  end_line = data.line2
  state = data.args

  local buf = vim.api.nvim_get_current_buf()

  for line_nb = start_line, end_line do
    local current_line = vim.api.nvim_buf_get_lines(buf, line_nb - 1, line_nb, false)[1]
    if current_line and current_line:match "%S" then
      set_checkbox(state, line_nb)
    end
  end
end
