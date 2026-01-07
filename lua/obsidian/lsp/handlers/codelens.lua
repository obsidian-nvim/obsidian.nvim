local obsidian = require "obsidian"

---@param buf integer
---@param update_backlinks boolean|?
---@return lsp.CodeLens[]|?
local update_footer = function(buf, update_backlinks)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local note = obsidian.Note.from_buffer(buf)
  if note == nil then
    return
  end
  local info = note:status(update_backlinks)
  if info == nil then
    return
  end
  local footer_format = Obsidian.opts.footer.format ---@cast footer_format -nil
  for k, v in pairs(info) do
    footer_format = footer_format:gsub("{{" .. k .. "}}", v)
  end
  -- local row0 = vim.api.nvim_buf_line_count(buf) - 1
  local row0 = 0
  return {
    {
      range = {
        start = { line = row0, character = 0 },
        ["end"] = { line = row0, character = 0 },
      },
      command = {
        title = footer_format,
        command = "",
        arguments = {},
      },
      data = {},
    },
  }
end

return function(_, callback)
  local buf = vim.api.nvim_get_current_buf()
  local lens = update_footer(buf, true)
  callback(nil, lens)
end
