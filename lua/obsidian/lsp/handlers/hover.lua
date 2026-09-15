local api = require "obsidian.api"
local util = require "obsidian.util"
local search = require "obsidian.search"
local attachment = require "obsidian.attachment"
local parse_block_id = require "obsidian.parse.block_id"

--- TODO: add hover support for bare/autolink URLs once cursor_link can detect them.
--- TODO: hover for attachments
--  TODO: header and block preview full section

---@param note obsidian.Note
---@param label string|?
---@param anchor_link string|?
---@param block_link string|?
---@return string|?
local function note_preview(note, label, anchor_link, block_link)
  local anchor, block

  if anchor_link then
    anchor = note:resolve_anchor_link(anchor_link)
    if not anchor then
      return nil
    end
  end

  if block_link then
    block = note:resolve_block(block_link)
    if not block then
      return nil
    end
  end

  return note:display_info { label = label, anchor = block and nil or anchor, block = block }
end

---@param location string
---@param label string|?
---@param callback fun(contents: string)
local function preview_link(location, label, callback)
  local is_uri, _scheme = util.is_uri(location)
  if is_uri then
    if _scheme == "http" or _scheme == "https" then
      -- TODO: cursor spinner
      util.fetch_url_markdown(location, function(lines, err)
        if not err then
          callback(table.concat(lines, "\n"))
        end
      end)
    else
      callback(("External uri:\n<" .. location .. ">"))
    end
    return
  end

  local is_attachment = attachment.is_attachment_path(location)

  if is_attachment then
    attachment._resolve_async(location, {}, function(path, err)
      if not err then
        callback(("Attachment:\n![[" .. path .. "]]"))
      end
      return
    end)
    return
  end

  local block_link, anchor_link
  location, block_link = util.strip_block_links(location)
  location, anchor_link = util.strip_anchor_links(location)

  if location == "" then
    local note = api.current_note(0, {
      collect_anchor_links = anchor_link ~= nil,
      collect_blocks = block_link ~= nil,
    })
    local contents = note and note_preview(note, label, anchor_link, block_link) or nil
    if contents then
      callback(contents)
    end
    return
  end

  search.resolve_note_async(location, function(notes)
    for _, note in ipairs(notes) do
      local contents = note_preview(note, label, anchor_link, block_link)
      if contents then
        callback(contents)
        return
      end
    end
  end, {
    notes = {
      collect_anchor_links = anchor_link ~= nil,
      collect_blocks = block_link ~= nil,
    },
  })
end

---@param _ lsp.HoverParams
---@param handler fun(_: any, result: lsp.Hover)
return function(_, handler, _)
  local cursor_ref = api.cursor_link()
  local cursor_tag = api.cursor_tag()
  local cursor_block
  local line = vim.api.nvim_get_current_line()
  local cursor_col = vim.api.nvim_win_get_cursor(0)[2]
  for _, block in ipairs(parse_block_id.extract(line)) do
    if block.range.start_col <= cursor_col and cursor_col < block.range.end_col then
      cursor_block = block.raw
      break
    end
  end

  if cursor_ref then
    local location, label, link_type = util.parse_link(cursor_ref)
    if not location or not link_type then
      return
    end

    location = vim.uri_decode(location)

    if link_type == "wiki" or link_type == "markdown" then
      preview_link(location, label, function(contents)
        handler(nil, { contents = contents })
      end)
    elseif link_type == "footnote" then
      local footnotes = require "obsidian.footnotes"
      local def = footnotes.find_definition(vim.api.nvim_get_current_buf(), location)
      if def then
        handler(nil, {
          contents = ("[^%s]: %s"):format(def.id, def.text),
        })
      else
        handler(nil, {
          contents = "*no footnote definition found*",
        })
      end
    end
  elseif cursor_block then
    local note = api.current_note(0, { collect_blocks = true })
    local contents = note and note_preview(note, nil, nil, cursor_block) or nil
    if contents then
      handler(nil, { contents = contents })
    end
  elseif cursor_tag then
    search.find_tags_async(cursor_tag, function(tag_locs)
      local notes_lookup = {}
      for _, tag_loc in ipairs(tag_locs) do
        notes_lookup[tostring(tag_loc.note.path)] = true
      end

      local note_count = vim.tbl_count(notes_lookup)
      handler(nil, {
        contents = string.format("**found in %s notes**", note_count),
      })
    end, {})
  else
    vim.notify("No note or tag found", 3)
  end
end
