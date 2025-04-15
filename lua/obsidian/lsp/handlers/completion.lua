-- TODO: completion for anchor, blocks
-- TODO: complete wiki format like nvim-cmp source and obsidan app

---@param client obsidian.Client
---@param params table
---@param handler function
return function(client, params, handler, _)
  local link_style = client.opts.preferred_link_style

  local function calc_insert_text(note)
    local link_text = client:format_link(note)
    if link_style == "markdown" then
      return link_text:sub(2)
    else
      return link_text:sub(3)
    end
  end

  local function handle_ref(partial)
    local items = {}
    client:find_notes_async(
      partial,
      vim.schedule_wrap(function(notes)
        for _, note in ipairs(notes) do
          local title = note.title
          if title and title:lower():find(vim.pesc(partial:lower())) then
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

  local function handle_tag(partial)
    local items = {}
    client:list_tags_async(
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
        handler(nil, { items = items })
      end)
    )
  end

  local uri = params.textDocument.uri
  local line_num = params.position.line
  local char_num = params.position.character
  local buf = vim.uri_to_bufnr(uri)

  local line_text = (vim.api.nvim_buf_get_lines(buf, line_num, line_num + 1, false)[1] or "")
  local text_before_cursor = line_text:sub(1, char_num)

  local ref_trigger_pattern = "[["
  if link_style == "markdown" then
    ref_trigger_pattern = "["
  end

  local tag_start = text_before_cursor:find("#", 1, true)
  local ref_start = text_before_cursor:find(ref_trigger_pattern, 1, true)

  if ref_start then
    local partial = text_before_cursor:sub(ref_start + 2)
    handle_ref(partial)
  elseif tag_start then
    local partial = text_before_cursor:sub(tag_start + 1)
    handle_tag(partial)
  end
end
