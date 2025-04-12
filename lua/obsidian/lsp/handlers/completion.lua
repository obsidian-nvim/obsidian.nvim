-- TODO: completion for anchor, blocks
-- TODO: complete wiki format like nvim-cmp source and obsidan app

return function(obsidian_client, params, handler, _)
  local link_style = obsidian_client.opts.preferred_link_style

  local function calc_insert_text(note, partial)
    local title = note.title
    if link_style == "markdown" then
      return title .. "](" .. note.path.filename .. ")"
    else
      return title .. "]]"
    end
  end

  local function build_ref_items(partial)
    local items = {}
    obsidian_client:find_notes_async(
      partial,
      vim.schedule_wrap(function(notes)
        for _, note in ipairs(notes) do
          local title = note.title
          if title and title:lower():find(vim.pesc(partial:lower())) then
            table.insert(items, {
              kind = "File",
              label = title,
              filterText = title,
              insertText = calc_insert_text(note, partial),
              labelDetails = { description = "Obsidian" },
            })
          end
        end
        handler(nil, { items = items })
      end)
    )
  end

  local function build_tag_items(partial)
    local items = {}
    obsidian_client:list_tags_async(
      partial,
      vim.schedule_wrap(function(tags)
        for _, tag in ipairs(tags) do
          if tag and tag:lower():find(vim.pesc(partial:lower())) then
            table.insert(items, {
              kind = "File",
              label = tag,
              filterText = tag,
              insertText = tag,
              labelDetails = { description = "ObsidianTag" },
            })
          end
        end
        handler(nil, {
          items = items,
        })
      end)
    )
  end

  local uri = params.textDocument.uri
  local line_num = params.position.line
  local char_num = params.position.character

  local file_path = vim.uri_to_fname(uri)
  local buf = vim.fn.bufnr(file_path, false)

  local line_text = (vim.api.nvim_buf_get_lines(buf, line_num, line_num + 1, false)[1] or "")
  local text_before_cursor = line_text:sub(1, char_num)

  local trigger_pattern = "[["
  if link_style == "markdown" then
    trigger_pattern = "["
  end

  local hastag_start = text_before_cursor:find("#", 1, true)

  local bracket_start = text_before_cursor:find(vim.pesc(trigger_pattern))

  if bracket_start then
    local partial = text_before_cursor:sub(bracket_start + 2)
    build_ref_items(partial)
  elseif hastag_start then
    local partial = text_before_cursor:sub(hastag_start + 1)
    build_tag_items(partial)
  end
end
