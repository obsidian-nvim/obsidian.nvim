-- TODO: completion for anchor, blocks
-- TODO: create item

local ref_trigger_pattern = {
  wiki = "[[",
  markdown = "[",
}

local find, sub, lower = string.find, string.sub, string.lower

---@param client obsidian.Client
---@param params table
---@param handler function
return function(client, params, handler, _)
  local link_style = client.opts.preferred_link_style
  local min_chars = client.opts.completion.min_chars

  local function calc_insert_text(note)
    local link_text = client:format_link(note)
    if link_style == "markdown" then
      return sub(link_text, 2)
    else
      return sub(link_text, 3)
    end
  end

  local function handle_ref(partial)
    local items = {}
    client:find_notes_async(
      partial,
      vim.schedule_wrap(function(notes)
        for _, note in ipairs(notes) do
          local title = note.title
          local pattern = vim.pesc(lower(partial))
          if title and find(lower(title), pattern) then
            table.insert(items, {
              kind = 17,
              label = title,
              filterText = title,
              insertText = calc_insert_text(note),
              labelDetails = { description = "Obsidian" },
              data = {
                file = note.path.filename,
                kind = "ref",
              },
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
              data = {
                kind = "tag",
              },
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
  local text_before_cursor = string.sub(line_text, 1, char_num)

  local tag_start = find(text_before_cursor, "#", 1, true)
  local ref_start = find(text_before_cursor, ref_trigger_pattern[link_style], 1, true)

  if ref_start then
    local partial = sub(text_before_cursor, ref_start + 2)
    if #partial >= min_chars then
      handle_ref(partial)
    end
  elseif tag_start then
    local partial = sub(text_before_cursor, tag_start + 1)
    if #partial >= min_chars then
      handle_tag(partial)
    end
  end
end
