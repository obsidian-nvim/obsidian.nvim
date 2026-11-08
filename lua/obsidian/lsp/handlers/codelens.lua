local Note = require "obsidian.note"

---@param lines string[]
---@param section obsidian.Section
---@return integer
local function section_words(lines, section)
  local count = 0
  -- Count only this heading's own body, not its title or child sections.
  for row = section.content_range.start_row, section.content_range.end_row - 1 do
    for _ in (lines[row + 1] or ""):gmatch "%S+" do
      count = count + 1
    end
  end
  return count
end

---@param params lsp.CodeLensParams
---@param callback fun(err: any, result: lsp.CodeLens[])
return function(params, callback)
  local bufnr = vim.uri_to_bufnr(params.textDocument.uri)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    callback(nil, {})
    return
  end

  local note = Note.from_buffer(bufnr, { collect_anchor_links = true })
  if not note then
    callback(nil, {})
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local sections = {}
  for _, section in ipairs(note.sections or {}) do
    if section.header then
      sections[#sections + 1] = section
    end
  end

  ---@type lsp.CodeLens[]
  local lenses = {}
  local pending = #sections
  if pending == 0 then
    callback(nil, lenses)
    return
  end

  for i, section in ipairs(sections) do
    local row = section.heading_range.start_row
    local words = section_words(lines, section)
    note:backlinks_async({ anchor = section.anchor }, function(matches)
      local count = #matches
      lenses[i] = {
        range = {
          start = { line = row, character = 0 },
          ["end"] = { line = row, character = 0 },
        },
        command = {
          title = count > 0 and (count == 1 and "1 backlink" or count .. " backlinks")
            or (words == 1 and "1 word" or words .. " words"),
          command = "obsidian.show_section_references",
          arguments = { params.textDocument.uri, row, section.anchor },
        },
      }
      pending = pending - 1
      if pending == 0 then
        callback(nil, lenses)
      end
    end)
  end
end
