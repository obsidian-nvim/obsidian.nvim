-- TODO: memoize?

local obsidian = require "obsidian"
local util = obsidian.util
local Search = obsidian.search
local find, sub, lower = string.find, string.sub, string.lower

local CmpType = {
  ref = 1,
  tag = 2,
  -- heading = 3,
  -- heading_all = 4,
  -- block = 5,
  -- block_all = 6,
}

local RefPatterns = {
  [CmpType.ref] = "[[",
  [CmpType.tag] = "#",
  -- [CmpType.heading] = "[[# ",
  -- [CmpType.heading_all] = "[[## ",
  -- [CmpType.block] = "[[^ ",
  -- [CmpType.block_all] = "[[^^ ",
}

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
local function label_to_new_text(label)
  local path = util.urlencode(label) .. ".md"
  local opts = { label = label, path = path }

  local format_func
  local style = Obsidian.opts.preferred_link_style
  if style == "markdown" then
    format_func = Obsidian.opts.markdown_link_func
  elseif style == "wiki" then
    format_func = Obsidian.opts.wiki_link_func
  else
    error "unimplemented link style"
  end
  return format_func(opts)
end

---@param label string
---@param path string
---@param new_text string
---@param range lsp.Range
---@return lsp.CompletionItem
local function gen_ref_item(label, path, new_text, range)
  return {
    kind = 17,
    label = label,
    textEdit = {
      range = range,
      newText = new_text,
    },
    labelDetails = { description = "Obsidian" },
    data = {
      file = path,
      kind = "ref",
    },
  }
end

local function gen_tag_item(tag)
  return {
    kind = 1,
    label = tag,
    insertText = tag,
    labelDetails = { description = "ObsidianTag" },
    data = { kind = "tag" },
  }
end

---@param label string
---@param range lsp.Range
---@return lsp.CompletionItem
local function gen_create_item(label, range)
  return {
    kind = 17,
    label = label .. " (create)",
    textEdit = {
      range = range,
      newText = label_to_new_text(label),
    },
    labelDetails = { description = "Obsidian" },
    command = {
      command = "create_note",
      arguments = { label },
    },
    data = {
      kind = "ref_create", -- TODO: resolve to a tooltip window
    },
  }
end

local function auto_accept(note, range)
  local edit = {
    documentChanges = {
      {
        textDocument = {
          uri = vim.uri_from_fname(tostring(note.path)),
          version = vim.NIL,
        },
        edits = {
          {
            range = range,
            newText = "[[" .. note.id .. "#",
          },
        },
      },
    },
  }
  vim.schedule(function()
    vim.lsp.util.apply_workspace_edit(edit, "utf-8")
    vim.api.nvim_win_set_cursor(0, {
      range.start.line + 1, -- 0 index to 1 index
      range["end"].character + 1, -- one char after
    })
  end)
end

local handle_bare_links = function(prefix, notes, range, handler)
  local items = {}

  local auto = false
  if vim.endswith(prefix, "#") then
    prefix = sub(prefix, 0, -2)
    auto = true
  else
    items[#items + 1] = gen_create_item(prefix, range) -- TODO: ?
  end

  local pattern = vim.pesc(lower(prefix))

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

  if auto then
    local note = note_lookup[matches[1]]
    if note then
      auto_accept(note, range)
    end
  else
    for _, match in ipairs(matches) do
      local note = note_lookup[match]
      if not res_lookup[note] then
        local link_text = note:format_link()
        items[#items + 1] = gen_ref_item(note.id, note.path.filename, link_text, range) -- TODO: label -> id title fname?
        res_lookup[note] = true
      end
    end
    handler(nil, { items = items })
  end
end

---@param partial string
---@param notes obsidian.Note[]
---@param anchor_link string
---@param callback function
local function handle_anchor_links(partial, notes, anchor_link, callback)
  -- TODO: calc current_note once
  -- TODO: handle two cases:
  -- 1. typing partial note name, no completeed text after cursor, insert the full link
  -- 2. jumped to heading, only insert anchor
  -- TODO: need to do more textEdit to insert additional #title to path so that app supports?
  local items = {}

  local pattern = vim.pesc(lower(partial))

  for _, note in ipairs(notes) do
    local id = note.id
    if id and find(lower(id), pattern) then
      local note_anchors = collect_matching_anchors(note, anchor_link)
      if not note_anchors then
        return
      end
      for _, anchor in ipairs(note_anchors) do
        items[#items + 1] = {
          kind = 17,
          label = anchor.header,
          filterText = anchor.header,
          insertText = anchor.header,
          -- textEdit = {
          --   range = {
          --     start = { line = line_num, character = insert_start },
          --     ["end"] = { line = line_num, character = insert_end },
          --   },
          --   newText = insert_snippet_marker(insert_text, style),
          -- },
          labelDetails = { description = "ObsidianAnchor" }, -- TODO: attach H1, H2
          data = {
            file = note.path.filename,
            kind = "anchor",
          },
        }
      end
    end
    callback(nil, { items = items })
  end
end

local function handle_block_links() end

local handlers = {}

handlers[CmpType.tag] = function(partial, range, handler)
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

handlers[CmpType.ref] = function(prefix, range, handler)
  local anchor_link, block_link
  prefix, anchor_link = util.strip_anchor_links(prefix)
  prefix, block_link = util.strip_block_links(prefix)

  local search_opts = Search._defaults
  search_opts.ignore_case = true

  local notes = Search.find_notes(prefix, {
    search = search_opts,
    notes = {
      collect_anchor_links = anchor_link ~= nil,
      collect_blocks = block_link ~= nil,
    },
  })

  if #notes == 0 then
    return handler(nil, { items = {} })
  end

  if anchor_link then
    handle_anchor_links(prefix, notes, anchor_link, handler)
  elseif block_link then
    -- handle_block_links(prefix, block_link, handler)
  else
    handle_bare_links(prefix, notes, range, handler)
  end
end

-- TODO: search.find_heading
local function handle_heading(client) end

---@param text string
---@param min_char integer
---@return integer? cmp_type
---@return string? prefix
---@return integer? boundary 0-indexed
local function get_cmp_type(text, min_char)
  for t, pattern in vim.spairs(RefPatterns) do -- spairs make sure ref is first
    local st, ed = find(text, pattern, 1, true)
    if st and ed then
      local prefix = sub(text, ed + 1)
      if #prefix >= min_char then -- TODO: unicode
        return t, prefix, st - 1
      end
    end
  end
end

---@param params lsp.CompletionParams
---@param callback function
return function(params, callback, _)
  local min_chars = Obsidian.opts.completion.min_chars
  ---@cast min_chars -nil

  local line_num = params.position.line -- 0-indexed
  local cursor_col = params.position.character -- 0-indexed

  local line_text = vim.api.nvim_buf_get_lines(0, line_num, line_num + 1, false)[1]
  local text_before = sub(line_text, 1, cursor_col)
  local t, prefix, ref_start = get_cmp_type(text_before, min_chars)

  callback = vim.schedule_wrap(callback)

  if not t then
    return callback(nil, {})
  end

  local range = {
    start = { line = line_num, character = ref_start },
    ["end"] = { line = line_num, character = cursor_col }, -- if auto parired
  }

  handlers[t](prefix, range, callback)
end
