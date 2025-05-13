-- TODO: completion for anchor, blocks
-- TODO: memoize?

local util = require "obsidian.util"
local find, sub, lower = string.find, string.sub, string.lower
local ref_trigger_pattern = {
  wiki = "[[",
  markdown = "[",
}

-- TODO: remove
local state = {
  ---@type obsidian.Note
  current_note = nil,
}

-- TODO:
local function insert_snippet_marker(text, style)
  if style == "markdown" then
    local pos = text:find "]"
    local a, b = sub(text, 1, pos - 1), sub(text, pos)
    return a .. "$1" .. b
  end
end

---Collect matching anchor links.
---@param note obsidian.Note
---@param anchor_link string?
---@return obsidian.note.HeaderAnchor[]?
local function collect_matching_anchors(note, anchor_link)
  ---@type obsidian.note.HeaderAnchor[]|?
  local matching_anchors
  if anchor_link then
    assert(note.anchor_links)
    matching_anchors = {}
    for anchor, anchor_data in pairs(note.anchor_links) do
      if vim.startswith(anchor, anchor_link) then
        table.insert(matching_anchors, anchor_data)
      end
    end

    if #matching_anchors == 0 then
      -- Unmatched, create a mock one.
      table.insert(matching_anchors, { anchor = anchor_link, header = string.sub(anchor_link, 2), level = 1, line = 1 })
    end
  end

  return matching_anchors
end

-- A more generic pure function, don't require label to exist
local function format_link(label, format_func)
  local path = util.urlencode(label) .. ".md"
  local opts = { label = label, path = path }
  return format_func(opts)
end

---@param label string
---@param path string
---@param new_text string
---@param range lsp.Range
---@return lsp.CompletionItem
local function gen_ref_item(label, path, new_text, range, style, is_snippet)
  return {
    kind = 17,
    label = label,
    filterText = label,
    insertTextFormat = 2, -- is snippet TODO: extract to config option
    textEdit = {
      range = range,
      newText = new_text,
      -- insert_snippet_marker(new_text, style),
    },
    labelDetails = { description = "Obsidian" },
    data = {
      file = path,
      kind = "ref",
    },
  }
end

---@param label string
---@param range lsp.Range
---@param format_func function
---@return lsp.CompletionItem
local function gen_create_item(label, range, format_func)
  return {
    kind = 17,
    label = label .. " (create)",
    filterText = label,
    textEdit = {
      range = range,
      newText = format_link(label, format_func),
    },
    labelDetails = { description = "Obsidian" },
    command = { -- runs after accept
      command = "create_note",
      arguments = { label },
    },
    data = {
      kind = "ref_create", -- TODO: resolve to a tooltip window
    },
  }
end

local handle_bare_links = function(client, partial, range, handler, format_func)
  local pattern = vim.pesc(lower(partial))

  local function match(title)
    return title and find(lower(title), pattern)
  end

  local style = client.opts.preferred_link_style

  client:find_notes_async(partial, function(notes)
    local items = {}
    for _, note in ipairs(notes or {}) do
      local title = note.title
      if match(title) then
        local link_text = client:format_link(note)
        items[#items + 1] = gen_ref_item(note.title, note.path.filename, link_text, range, style)
      end
    end
    items[#items + 1] = gen_create_item(partial, range, format_func)
    handler(nil, { items = items })
  end)
end

---@param client obsidian.Client
local function handle_ref(client, partial, ref_start, cursor_col, line_num, handler)
  ---@type string|?
  local anchor_link
  partial, anchor_link = util.strip_anchor_links(partial)
  local style = client.opts.preferred_link_style

  local range = {
    start = { line = line_num, character = ref_start },
    ["end"] = { line = line_num, character = cursor_col }, -- if auto parired
  }

  local format_func
  if style == "markdown" then
    format_func = client.opts.markdown_link_func
  else
    format_func = client.opts.wiki_link_func
  end

  if not anchor_link then
    handle_bare_links(client, partial, range, handler, format_func)
  else
    local Note = require "obsidian.note"
    -- state.current_note = state.current_note or client:find_notes(partial)[2]
    -- TODO: calc current_note once
    -- TODO: handle two cases:
    -- 1. typing partial note name, no completeed text after cursor, insert the full link
    -- 2. jumped to heading, only insert anchor
    -- TODO: need to do more textEdit to insert additional #title to path so that app supports?
    local items = {}
    client:find_notes_async(
      partial,
      vim.schedule_wrap(function(notes)
        for _, note in ipairs(notes) do
          local title = note.title
          local pattern = vim.pesc(lower(partial))
          if title and find(lower(title), pattern) then
            local note2 = Note.from_file(note.path.filename, { collect_anchor_links = true })

            local note_anchors = collect_matching_anchors(note2, anchor_link)
            if not note_anchors then
              return
            end
            for _, anchor in ipairs(note_anchors) do
              items[#items + 1] = {
                kind = 17,
                label = anchor.header,
                filterText = anchor.header,
                insertText = anchor.header,
                -- insertTextFormat = 2, -- is snippet
                -- textEdit = {
                --   range = {
                --     start = { line = line_num, character = insert_start },
                --     ["end"] = { line = line_num, character = insert_end },
                --   },
                --   newText = insert_snippet_marker(insert_text, style),
                -- },
                labelDetails = { description = "ObsidianAnchor" },
                data = {
                  file = note.path.filename,
                  kind = "anchor",
                },
              }
            end
          end
          handler(nil, { items = items })
        end
      end)
    )
  end
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

local function handle_heading(client)
  -- TODO: client:find_headings_async
  -- client:find_
end

-- util.BLOCK_PATTERN = "%^[%w%d][%w%d-]*"
local anchor_trigger_pattern = {
  markdown = "%[%S+#(%w*)",
}

local heading_trigger_pattern = "[##"

local CmpType = {
  ref = 1,
  tag = 2,
  anchor = 3,
}

---@param text string
---@param style obsidian.config.LinkStyle
---@param min_char integer
---@return integer?
---@return string?
---@return integer?
local function get_type(text, style, min_char)
  local ref_start = find(text, ref_trigger_pattern[style], 1, true)
  local tag_start = find(text, "#", 1, true)
  -- local heading_start = find(text, heading_trigger_pattern, 1, true)

  if ref_start then
    local partial = sub(text, ref_start + #ref_trigger_pattern[style])
    if #partial >= min_char then
      return CmpType.ref, partial, ref_start
    end
  elseif tag_start then
    local partial = sub(text, tag_start + 1)
    if #partial >= min_char then
      return CmpType.tag, partial, tag_start
    end
    -- elseif heading_start then
    --   local partial = sub(text, heading_start + #heading_trigger_pattern)
    --   if #partial >= min_char then
    --     return CmpType.anchor, partial, heading_start
    --   end
  end
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
  local text_before = sub(line_text, 1, char_num)
  local t, partial, start = get_type(text_before, link_style, min_chars)

  if t == CmpType.ref then
    handle_ref(client, partial, start - 1, char_num, line_num, handler)
  elseif t == CmpType.tag then
    handle_tag(client, partial, handler)
  elseif t == CmpType.anchor then
  else
    return
  end
end
