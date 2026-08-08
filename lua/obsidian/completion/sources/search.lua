local M = {}

---@type lsp.CompletionList
local EMPTY_RESPONSE = { isIncomplete = true, items = {} }

local prefixes = {
  {
    label = "path:",
    detail = "Match text in a vault-relative path",
    kind = vim.lsp.protocol.CompletionItemKind.Keyword,
  },
  {
    label = "file:",
    detail = "Match text in a filename",
    kind = vim.lsp.protocol.CompletionItemKind.Keyword,
  },
  {
    label = "line:",
    detail = "Match terms on the same line",
    kind = vim.lsp.protocol.CompletionItemKind.Keyword,
  },
  {
    label = "section:",
    detail = "Match terms in the same section",
    kind = vim.lsp.protocol.CompletionItemKind.Keyword,
  },
  {
    label = "tag:",
    detail = "Match an exact Obsidian tag",
    kind = vim.lsp.protocol.CompletionItemKind.Keyword,
  },
  {
    label = "[property]",
    detail = "Match a frontmatter property",
    kind = vim.lsp.protocol.CompletionItemKind.Property,
  },
}

---@param request obsidian.completion.Request
---@return string prefix
---@return integer insert_start
---@return integer insert_end
local function completion_context(request)
  local before = request.cursor_before_line
  local after = request.cursor_after_line
  local token_start = before:find "[^%s%(]*$" or (#before + 1)
  local prefix = before:sub(token_start)

  if vim.startswith(prefix, "-") then
    token_start = token_start + 1
    prefix = prefix:sub(2)
  end

  local suffix = after:match "^[^%s%)]*" or ""
  return prefix, token_start - 1, request.character + #suffix
end

---@param callback fun(resp: lsp.CompletionList)
---@param request  obsidian.completion.Request
function M.process_completion(callback, request)
  if vim.b[request.bufnr].obsidian_completion_source ~= "search_query" then
    callback(EMPTY_RESPONSE)
    return
  end

  local prefix, insert_start, insert_end = completion_context(request)
  local prefix_lower = string.lower(prefix)
  local items = {}

  for index, candidate in ipairs(prefixes) do
    local matches
    if vim.startswith(prefix, "[") then
      matches = candidate.label == "[property]" and vim.startswith("[property]", prefix_lower)
    else
      matches = candidate.label ~= "[property]" and vim.startswith(candidate.label, prefix_lower)
    end

    if matches then
      items[#items + 1] = {
        label = candidate.label,
        filterText = candidate.label,
        sortText = string.format("%02d", index),
        kind = candidate.kind,
        detail = candidate.detail,
        textEdit = {
          newText = candidate.label,
          range = {
            ["start"] = { line = request.line, character = insert_start },
            ["end"] = { line = request.line, character = insert_end },
          },
        },
      }
    end
  end

  callback { isIncomplete = true, items = items }
end

return M
