local util = require "obsidian.util"

---@param params lsp.CodeActionParams
---@param callback fun(err: any, result: lsp.CodeAction[]?)
return function(params, callback)
  local uri = params.textDocument.uri
  local line = params.range.start.line -- 0-indexed
  local buf = vim.uri_to_bufnr(uri)

  if not vim.api.nvim_buf_is_valid(buf) then
    return callback(nil, {})
  end

  local line_text = vim.api.nvim_buf_get_lines(buf, line, line + 1, false)[1]
  if not line_text then
    return callback(nil, {})
  end

  ---@type lsp.CodeAction[]
  local actions = {}

  local header_match = util.parse_header(line_text)
  if header_match then
    actions[#actions + 1] = {
      title = "Extract section into new note",
      kind = "refactor.extract",
      command = {
        title = "Extract section into new note",
        command = "obsidian.extract_section",
        arguments = { uri, line },
      },
    }
  end

  callback(nil, actions)
end
