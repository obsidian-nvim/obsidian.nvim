local RefsSourceBase = require "obsidian.completion.sources.base.refs"
local TagsSourceBase = require "obsidian.completion.sources.base.tags"
local NewNoteSourceBase = require "obsidian.completion.sources.base.new"

--- LSP-standard response shapes.
local incomplete_response = { isIncomplete = true }
local complete_response = { isIncomplete = true, items = {} }

--- Build a base-class Request from LSP CompletionParams.
---
--- The base classes expect:
---   request.context.bufnr            (integer)
---   request.context.cursor_before_line (string)
---   request.context.cursor_after_line  (string)
---   request.context.cursor.row       (1-indexed line)
---   request.context.cursor.col       (1-indexed byte column)
---   request.context.cursor.line      (1-indexed line, used by tags for frontmatter)
---   request.context.cursor.character (0-indexed UTF-8 offset, used by refs.can_complete)
---
---@param params lsp.CompletionParams
---@return obsidian.completion.sources.base.Request
local function build_request(params)
  local uri = params.textDocument.uri
  local bufnr = vim.uri_to_bufnr(uri)

  -- LSP position is 0-indexed line, 0-indexed character (UTF-16 by default, but
  -- obsidian-ls advertises utf-8 offset encoding).
  local lsp_line = params.position.line
  local lsp_char = params.position.character

  -- Fetch the full line text from the buffer.
  local lines = vim.api.nvim_buf_get_lines(bufnr, lsp_line, lsp_line + 1, false)
  local line_text = lines[1] or ""

  -- Convert 0-indexed character to 1-indexed byte column.
  local col = lsp_char + 1

  local cursor_before_line = line_text:sub(1, col - 1)
  local cursor_after_line = line_text:sub(col)

  return {
    context = {
      bufnr = bufnr,
      cursor_before_line = cursor_before_line,
      cursor_after_line = cursor_after_line,
      cursor = {
        row = lsp_line + 1, -- 1-indexed
        col = col, -- 1-indexed byte
        line = lsp_line + 1, -- 1-indexed, used by tags for frontmatter detection
        character = lsp_char, -- 0-indexed, used by refs.can_complete
      },
    },
  }
end

--- Instantiate a source with LSP-standard response fields.
---@generic T
---@param Source { new: fun(): T }
---@return T
local function make_source(Source)
  local source = Source.new()
  source.incomplete_response = incomplete_response
  source.complete_response = complete_response
  return source
end

--- Merge two LSP CompletionList tables.
---@param a lsp.CompletionList
---@param b lsp.CompletionList
---@return lsp.CompletionList
local function merge_results(a, b)
  local items = {}
  for _, item in ipairs(a.items or {}) do
    items[#items + 1] = item
  end
  for _, item in ipairs(b.items or {}) do
    items[#items + 1] = item
  end
  return {
    isIncomplete = a.isIncomplete or b.isIncomplete,
    items = items,
  }
end

---@param params lsp.CompletionParams
---@param callback fun(err: any, result: lsp.CompletionList)
return function(params, callback, _)
  local request = build_request(params)

  -- We'll collect results from up to 3 sources (refs, tags, new note) and merge
  -- them before calling the LSP callback. Because each source is async, we use
  -- a simple counter to know when all have finished.
  local pending = 0
  local merged = { isIncomplete = true, items = {} }

  local function on_source_done(result)
    if result and result.items then
      merged = merge_results(merged, result)
    end
    pending = pending - 1
    if pending == 0 then
      callback(nil, merged)
    end
  end

  -- Refs source.
  local refs_source = make_source(RefsSourceBase)
  pending = pending + 1
  local refs_cc = refs_source:new_completion_context(on_source_done, request)
  refs_source:process_completion(refs_cc)

  -- Tags source.
  local tags_source = make_source(TagsSourceBase)
  pending = pending + 1
  local tags_cc = tags_source:new_completion_context(on_source_done, request)
  tags_source:process_completion(tags_cc)

  -- New note source (only if configured).
  if Obsidian.opts.completion.create_new then
    local new_source = make_source(NewNoteSourceBase)
    pending = pending + 1
    local new_cc = new_source:new_completion_context(on_source_done, request)
    new_source:process_completion(new_cc)
  end

  -- If no sources were started (shouldn't happen, but guard against it),
  -- return an empty result immediately.
  if pending == 0 then
    callback(nil, merged)
  end
end
