local log = require "obsidian.log"
local api = require "obsidian.api"
local picker = require "obsidian.picker"
local link_suggestion = require "obsidian.note.link_suggestion"
local Note = require "obsidian.note"
local util = require "obsidian.util"

---Apply a link suggestion to a specific (possibly unlisted) buffer.
---@param bufnr integer
---@param suggestion obsidian.LinkSuggestion
---@param candidate obsidian.LinkSuggestionCandidate
local function apply_to_buf(bufnr, suggestion, candidate)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return log.warn "Buffer is no longer valid"
  end

  local range = suggestion.range
  local current_text =
    vim.api.nvim_buf_get_text(bufnr, range.start_row, range.start_col, range.end_row, range.end_col, {})
  if #current_text ~= 1 or current_text[1] ~= suggestion.text then
    return log.warn "Link suggestion is no longer current (file may have changed)"
  end

  vim.api.nvim_buf_set_text(
    bufnr,
    range.start_row,
    range.start_col,
    range.end_row,
    range.end_col,
    { candidate.new_text }
  )
  -- Flush the buffer to disk.
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd "write"
  end)
  require("obsidian.ui").update(bufnr)
end

return function()
  local bufnr = vim.api.nvim_get_current_buf()
  local note = api.current_note(bufnr, { max_lines = vim.api.nvim_buf_line_count(bufnr) })
  if not note then
    return log.info "Not in a note"
  end

  local cache = require "obsidian.cache"
  if not cache.is_enabled() then
    return log.warn "Cache is not enabled; cannot search for unlinked mentions"
  end

  local current_path = tostring(note.path)

  -- Build the symbol list from the current note's title + aliases.
  -- We use link_suggestion.symbols with include_current=true then filter to only
  -- symbols that resolve to the current note's path.
  local all_symbols = link_suggestion.symbols(current_path, { include_current = true })
  ---@type obsidian.LinkSuggestionSymbol[]
  local self_symbols = {}
  for _, sym in ipairs(all_symbols) do
    for _, tp in ipairs(sym.target_paths) do
      if vim.fs.normalize(tp) == vim.fs.normalize(current_path) then
        self_symbols[#self_symbols + 1] = sym
        break
      end
    end
  end

  if #self_symbols == 0 then
    return log.info "No symbols found for current note (title/aliases not in cache)"
  end

  local ok, cached_rows = pcall(cache.notes.all)
  if not ok or not cached_rows then
    return log.warn "Cache not available"
  end

  ---@type obsidian.PickerEntry[]
  local entries = {}

  local dir = api.resolve_workspace_dir(current_path)

  local function path_exists(path)
    return vim.uv.fs_stat(path) ~= nil
  end

  for path, _ in pairs(cached_rows) do
    local norm_path = vim.fs.normalize(path)
    if norm_path == vim.fs.normalize(current_path) then
      goto continue
    end

    -- Fast pre-filter: check if any symbol text appears in the raw file
    -- before doing a full parse.
    local raw_file = io.open(path, "r")
    if not raw_file then
      goto continue
    end
    local raw_content = raw_file:read "*a"
    raw_file:close()

    local has_candidate = false
    for _, sym in ipairs(self_symbols) do
      if raw_content:lower():find(sym.text_lower, 1, true) then
        has_candidate = true
        break
      end
    end

    if not has_candidate then
      goto continue
    end

    -- Full parse: load the note and scan line by line.
    local ok_note, other_note = pcall(Note.from_file, path)
    if not ok_note or not other_note then
      goto continue
    end

    local fm_end = other_note.frontmatter_end_line or 1
    local source_dir = vim.fs.dirname(norm_path)
    local code_fence = nil

    for row = fm_end, #other_note.contents do
      local line = other_note.contents[row]
      ---@cast line string
      local fence = line:match "^%s*(```+)" or line:match "^%s*(~~~+)"
      if fence then
        if not code_fence then
          code_fence = fence
        elseif fence:sub(1, 1) == code_fence:sub(1, 1) and #fence >= #code_fence then
          code_fence = nil
        end
      elseif not code_fence then
        local line_suggestions = link_suggestion.find_in_line(line, row, self_symbols, path_exists, source_dir)
        for _, suggestion in ipairs(line_suggestions) do
          for _, candidate in ipairs(suggestion.candidates) do
            local lnum = suggestion.range.start_row + 1
            local col = suggestion.range.start_col + 1
            local short_path = vim.fn.fnamemodify(path, ":t")
            entries[#entries + 1] = {
              filename = path,
              lnum = lnum,
              col = col,
              text = string.format(
                "%s:%d:%d  %s → %s",
                short_path,
                lnum,
                col,
                suggestion.text,
                candidate.new_text
              ),
              user_data = { path = path, suggestion = suggestion, candidate = candidate },
            }
          end
        end
      end
    end

    ::continue::
  end

  if #entries == 0 then
    return log.info "No unlinked incoming mentions found"
  end

  picker.select(entries, {
    prompt = "Incoming unlinked mentions",
    allow_multiple = true,
    preview_item = function(entry)
      ---@cast entry obsidian.PickerEntry
      local preview = util.preview_path(entry.filename)
      preview.pos = { entry.lnum or 1, entry.col and math.max(entry.col - 1, 0) or 0 }
      return preview
    end,
  }, function(choices)
    if not choices then
      return
    end
    for _, choice in ipairs(choices) do
      ---@cast choice obsidian.PickerEntry
      local data = choice.user_data
      if not data then
        goto next_choice
      end

      -- Load/create the buffer for the target file.
      local target_bufnr = vim.fn.bufnr(data.path)
      local was_loaded = target_bufnr > 0 and vim.api.nvim_buf_is_loaded(target_bufnr)
      if target_bufnr < 1 then
        target_bufnr = vim.fn.bufadd(data.path)
      end
      vim.fn.bufload(target_bufnr)

      apply_to_buf(target_bufnr, data.suggestion, data.candidate)

      -- If the file was not previously loaded, unload it after editing to avoid
      -- polluting the buffer list.
      if not was_loaded then
        vim.api.nvim_buf_delete(target_bufnr, { unload = true })
      end

      ::next_choice::
    end
  end)
end
