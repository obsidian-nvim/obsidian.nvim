local toggle_checkbox = require("obsidian.api").toggle_checkbox

---@param client obsidian.Client
---@param data CommandArgs
return function(client, data)
  local start_line, end_line
  local checkboxes = vim.tbl_keys(client.opts.ui.checkboxes)
  start_line = data.line1
  end_line = data.line2

  local buf = vim.api.nvim_get_current_buf()

  for line_nb = start_line, end_line do
    local current_line = vim.api.nvim_buf_get_lines(buf, line_nb - 1, line_nb, false)[1]
    if current_line and current_line:match "%S" then
      table.sort(checkboxes, function(a, b)
        return (client.opts.ui.checkboxes[a].order or 1000) < (client.opts.ui.checkboxes[b].order or 1000)
      end)
      toggle_checkbox(checkboxes, line_nb)
    end
  end
end
