local toggle_checkbox = require("obsidian.api").toggle_checkbox

---@param data obsidian.CommandArgs
return function(data)
  local start_line, end_line
  local checkboxes = Obsidian.opts.checkbox.order
  start_line = data.line1
  end_line = data.line2

  local buf = vim.api.nvim_get_current_buf()

  for line_nb = start_line, end_line do
    local current_line = vim.api.nvim_buf_get_lines(buf, line_nb - 1, line_nb, false)[1]
    if current_line and current_line:match "%S" then
      toggle_checkbox(checkboxes, line_nb)
    end
  end
end
