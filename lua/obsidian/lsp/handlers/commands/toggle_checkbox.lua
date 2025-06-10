local util = require "obsidian.util"
local config = require "obsidian.lsp.config"

local gen_checkbox_edit = function(uri, newText, line, start)
  local edit = {
    range = {
      start = { line = line, character = start or 0 },
      ["end"] = { line = line, character = (start or -1) + 1 },
    },
    newText = newText,
  }
  return {
    changes = {
      [uri] = { edit },
    },
  }
end

---@param client obsidian.Client
local gen_checkbox_edits = function(client, buf)
  local line_num = unpack(vim.api.nvim_win_get_cursor(0)) - 1 -- 0-indexed
  local line = vim.api.nvim_buf_get_lines(buf, line_num, line_num + 1, false)[1]
  local uri = vim.uri_from_bufnr(buf)

  local checkboxes = vim.tbl_keys(client.opts.ui.checkboxes)

  local defualt_checkbox_style = config.checkboxs.style

  if util.is_checkbox(line) then
    for i, check_char in ipairs(checkboxes) do
      local start = string.find(line, "%[" .. vim.pesc(check_char))
      if start then
        i = i % #checkboxes
        return gen_checkbox_edit(uri, checkboxes[i + 1], line_num, start)
      end
    end
  else
    return gen_checkbox_edit(uri, defualt_checkbox_style, line_num, nil)
  end
end

return function(client, params)
  local buf = vim.api.nvim_get_current_buf()
  local edits = gen_checkbox_edits(client, buf)
  vim.lsp.util.apply_workspace_edit(edits, "utf-8")
end
