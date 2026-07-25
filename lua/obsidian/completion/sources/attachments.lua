local attachment = require "obsidian.attachment"
local completion = require "obsidian.completion.refs"

local M = {}

---@type lsp.CompletionList
local EMPTY_RESPONSE = {
  isIncomplete = true,
  items = {},
}

---@param callback fun(resp: lsp.CompletionList)
---@param request obsidian.completion.Request
function M.process_completion(callback, request)
  local can_complete, term, insert_start, insert_end = completion.can_complete(request)
  if not can_complete or not term or #term < Obsidian.opts.completion.min_chars or string.find(term, "#", 1, true) then
    callback(EMPTY_RESPONSE)
    return
  end

  ---@cast insert_start -nil
  ---@cast insert_end -nil
  attachment.find_async(term, function(matches)
    ---@type lsp.CompletionItem[]
    local items = {}
    for _, match in ipairs(matches) do
      local format = Obsidian.opts.link.format
      local basename_target = attachment.resolve_attachment_path(match.basename, request.bufnr)
      if
        format == "shortest"
        and (match.ambiguous or vim.fs.normalize(basename_target) ~= vim.fs.normalize(match.path))
      then
        format = "absolute"
      end
      local new_text = attachment.format_reference(match.path, {
        bufnr = request.bufnr,
        format = format,
        label = match.basename,
      })
      items[#items + 1] = {
        label = new_text,
        detail = match.rel_path,
        sortText = match.basename .. " " .. match.rel_path,
        filterText = completion.get_filter_text(match.basename),
        kind = vim.lsp.protocol.CompletionItemKind.File,
        textEdit = {
          newText = new_text,
          range = {
            start = {
              line = request.line,
              character = insert_start,
            },
            ["end"] = {
              line = request.line,
              character = insert_end,
            },
          },
        },
      }
    end

    callback {
      isIncomplete = true,
      items = items,
    }
  end)
end

return M
