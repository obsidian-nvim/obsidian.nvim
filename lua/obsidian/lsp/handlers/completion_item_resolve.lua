local MAX_PREVIEW_LINES = 80

---@param path string
---@return string|?
local function read_preview(path)
  if vim.fn.filereadable(path) ~= 1 then
    return nil
  end

  local ok, lines = pcall(vim.fn.readfile, path, "", MAX_PREVIEW_LINES + 1)
  if not ok or not lines then
    return nil
  end

  local truncated = #lines > MAX_PREVIEW_LINES
  if truncated then
    lines[MAX_PREVIEW_LINES + 1] = nil
  end

  local value = table.concat(lines, "\n")
  if truncated then
    value = value .. "\n\n…"
  end

  return value
end

---@param item lsp.CompletionItem
---@param handler fun(_: any, res: lsp.CompletionItem)
return function(item, handler)
  local data = item.data
  local path = type(data) == "table" and data.obsidian_preview_path or nil
  if type(path) == "string" then
    local preview = read_preview(path)
    if preview then
      item.documentation = {
        kind = "markdown",
        value = preview,
      }
    end
  end

  handler(nil, item)
end
