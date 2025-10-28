-- TODO: completion for anchor, blocks
-- TODO: memoize?

local obsidian = require "obsidian"
local util = obsidian.util
local Search = obsidian.search
local find, sub, lower = string.find, string.sub, string.lower

-- TODO:
local CmpType = {
  ref = 1,
  tag = 2,
  anchor = 3,
}

---@return function
local function get_format_func()
  local format_func
  local style = Obsidian.opts.preferred_link_style
  if style == "markdown" then
    format_func = Obsidian.opts.markdown_link_func
  elseif style == "wiki" then
    format_func = Obsidian.opts.wiki_link_func
  else
    error "unimplemented"
  end
  return format_func
end

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
local function gen_ref_item(label, path, new_text, range, is_snippet)
  return {
    kind = 17,
    label = label,
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
    -- insertTextFormat = 1, -- is snippet TODO: extract to config option
  }
end

local function gen_tag_item(tag)
  return {
    kind = 1,
    label = tag,
    filterText = tag,
    insertText = tag,
    labelDetails = { description = "ObsidianTag" },
    data = { kind = "tag" },
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

local handle_bare_links = function(partial, range, handler)
  local items = {}
  items[#items + 1] = gen_create_item(partial, range, get_format_func())

  local pattern = vim.pesc(lower(partial))
  local notes = Search.find_notes(pattern)

  if #notes == 0 then
    return handler(nil, { items = items })
  end

  local note_lookup = {}
  local queries = {}
  local res_lookup = {}

  for _, note in ipairs(notes) do
    if note.id then -- TODO: match case
      note_lookup[note.id] = note
      queries[#queries + 1] = note.id
    end
  end

  local matches = vim.fn.matchfuzzy(queries, pattern, { limit = 10 }) -- TOOD: config? lower?

  for _, match in ipairs(matches) do
    local note = note_lookup[match]
    if not res_lookup[note] then
      local link_text = note:format_link()
      items[#items + 1] = gen_ref_item(note.id, note.path.filename, link_text, range) -- TODO: label -> id title fname?
      res_lookup[note] = true
    end
  end

  handler(nil, {
    items = items,
  })
end

local function handle_anchor_links(partial, anchor_link, handler)
  local Note = require "obsidian.note"
  -- state.current_note = state.current_note or client:find_notes(partial)[2]
  -- TODO: calc current_note once
  -- TODO: handle two cases:
  -- 1. typing partial note name, no completeed text after cursor, insert the full link
  -- 2. jumped to heading, only insert anchor
  -- TODO: need to do more textEdit to insert additional #title to path so that app supports?
  local items = {}
  Search.find_notes(partial, function(notes)
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
end

local function handle_ref(partial, range, handler)
  ---@type string|?
  local anchor_link
  partial, anchor_link = util.strip_anchor_links(partial)

  if not anchor_link then
    handle_bare_links(partial, range, handler)
  else
    handle_anchor_links(partial, anchor_link, handler)
  end
end

local function handle_tag(partial, handler)
  local items = {}
  local tags = vim
    .iter(Search.find_tags("", {}))
    :map(function(match)
      return match.tag
    end)
    :totable()
  tags = util.tbl_unique(tags)
  for _, tag in ipairs(tags) do
    if tag and tag:lower():find(vim.pesc(partial:lower())) then
      items[#items + 1] = gen_tag_item(tag)
    end
  end
  handler(nil, { items = items })
end

local function handle_heading(client)
  -- TODO: search.find_heading
end

-- util.BLOCK_PATTERN = "%^[%w%d][%w%d-]*"
local anchor_trigger_pattern = {
  markdown = "%[%S+#(%w*)",
}

local heading_trigger_pattern = "[##"

---@param text string
---@param style obsidian.config.LinkStyle
---@param min_char integer
---@return integer?
---@return string?
---@return integer?
local function get_type(text, min_char)
  local ref_start = find(text, "[[", 1, true)
  local tag_start = find(text, "#", 1, true)
  -- local heading_start = find(text, heading_trigger_pattern, 1, true)

  if ref_start then
    local partial = sub(text, ref_start + 2)
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

---@param params lsp.CompletionParams
---@param handler function
return function(params, handler, _)
  local min_chars = Obsidian.opts.completion.min_chars
  ---@cast min_chars -nil

  local line_num = params.position.line -- 0-indexed
  local cursor_col = params.position.character -- 0-indexed

  local line_text = vim.api.nvim_buf_get_lines(0, line_num, line_num + 1, false)[1]
  local text_before = sub(line_text, 1, cursor_col)
  local t, partial, start = get_type(text_before, min_chars)

  local ref_start = start and start - 1

  local range = {
    start = { line = line_num, character = ref_start },
    ["end"] = { line = line_num, character = cursor_col }, -- if auto parired
  }

  handler = vim.schedule_wrap(handler)

  if t == CmpType.ref then
    handle_ref(partial, range, handler)
  elseif t == CmpType.tag then
    handle_tag(partial, handler)
  elseif t == CmpType.anchor then
  end
end
