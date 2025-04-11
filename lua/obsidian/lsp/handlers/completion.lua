local obsidian_client = require("obsidian").get_client()
local link_style = obsidian_client.opts.preferred_link_style

local function calc_insert_text(note, text_after_cursor)
  -- TODO: consider incomplete
  if link_style == "markdown" then
    return note.title .. "](" .. note.path.filename .. ")"
  else
    return note.title .. "]]"
  end
end

return function(_, params, handler, _)
  local uri = params.textDocument.uri
  local line_num = params.position.line
  local char_num = params.position.character

  local file_path = vim.uri_to_fname(uri)
  local buf = vim.fn.bufnr(file_path, false)

  local line_text = (vim.api.nvim_buf_get_lines(buf, line_num, line_num + 1, false)[1] or "")
  local text_before_cursor = line_text:sub(1, char_num)

  local trigger_pattern = "%[%[.*$"
  if link_style == "markdown" then
    trigger_pattern = "%[.*$"
  end

  local bracket_start = text_before_cursor:find(trigger_pattern)

  if not bracket_start then
    handler(nil, { items = {} }, params.context)
    return
  end

  local partial = text_before_cursor:sub(bracket_start + 2)

  local items = {}
  obsidian_client:find_notes_async(
    partial,
    vim.schedule_wrap(function(notes)
      for _, note in ipairs(notes) do
        local title = note.title
        if title and title:lower():find(partial:lower(), 1, true) then
          table.insert(items, {
            kind = "File",
            label = title,
            filterText = title,
            insertText = calc_insert_text(note),
            labelDetails = { description = "Obsidian" },
          })
        end
      end
      handler(nil, { items = items })
    end)
  )
end
