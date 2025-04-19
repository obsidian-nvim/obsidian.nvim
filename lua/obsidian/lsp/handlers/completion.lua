-- TODO: completion for anchor, blocks
-- TODO: create item
-- TODO: memoize?

local ref_trigger_pattern = {
  wiki = "[[",
  markdown = "[",
}

local util = require "obsidian.util"

local find, sub, lower = string.find, string.sub, string.lower

---@param note obsidian.Note
---@param insert_text string
---@param insert_start integer
---@param insert_end integer
---@param line_num integer
---@return lsp.CompletionItem
local function calc_ref_item(note, insert_text, insert_start, insert_end, line_num)
  return {
    kind = 17,
    label = note.title,
    filterText = note.title,
    textEdit = {
      range = {
        start = { line = line_num, character = insert_start },
        ["end"] = { line = line_num, character = insert_end },
      },
      newText = insert_text,
    },
    labelDetails = { description = "Obsidian" },
    data = {
      file = note.path.filename,
      kind = "ref",
    },
  }
end

local function handle_ref(client, partial, ref_start, cursor_col, line_num, handler)
  ---@type string|?
  -- local block_link
  -- cc.search, block_link = util.strip_block_links(cc.search)
  --
  -- ---@type string|?
  -- local anchor_link
  -- cc.search, anchor_link = util.strip_anchor_links(cc.search)

  local items = {}
  client:find_notes_async(
    partial,
    vim.schedule_wrap(function(notes)
      for _, note in ipairs(notes) do
        local title = note.title
        local pattern = vim.pesc(lower(partial))
        if title and find(lower(title), pattern) then
          local link_text = client:format_link(note)
          items[#items + 1] = calc_ref_item(note, link_text, ref_start, cursor_col, line_num)
        end
      end
      handler(nil, { items = items })
    end)
  )
end

local function calc_tag_item(tag)
  return {
    kind = "File",
    label = tag,
    filterText = tag,
    insertText = tag,
    labelDetails = { description = "ObsidianTag" },
    data = { kind = "tag" },
  }
end

local function handle_tag(client, partial, handler)
  local items = {}
  client:list_tags_async(
    partial,
    vim.schedule_wrap(function(tags)
      for _, tag in ipairs(tags) do
        if tag and tag:lower():find(vim.pesc(partial:lower())) then
          items[#items + 1] = calc_tag_item(tag)
        end
      end
      handler(nil, { items = items })
    end)
  )
end

---@param client obsidian.Client
---@param params table
---@param handler function
return function(client, params, handler, _)
  local link_style = client.opts.preferred_link_style
  local min_chars = client.opts.completion.min_chars

  local uri = params.textDocument.uri
  local line_num = params.position.line
  local char_num = params.position.character

  local buf = vim.uri_to_bufnr(uri)
  local line_text = vim.api.nvim_buf_get_lines(buf, line_num, line_num + 1, false)[1]

  print(util.strip_anchor_links(line_text))
  print(util.strip_block_links(line_text))

  local text_before_cursor = sub(line_text, 1, char_num)

  local tag_start = find(text_before_cursor, "#", 1, true)
  local ref_start = find(text_before_cursor, ref_trigger_pattern[link_style], 1, true)

  if ref_start then
    local partial = sub(text_before_cursor, ref_start + #ref_trigger_pattern[link_style])
    if #partial >= min_chars then
      handle_ref(client, partial, ref_start - 1, char_num, line_num, handler)
    end
  elseif tag_start then
    local partial = sub(text_before_cursor, tag_start + 1)
    if #partial >= min_chars then
      handle_tag(client, partial, handler)
    end
  end
end
