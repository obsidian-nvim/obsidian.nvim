local Ref = require "obsidian.completion.sources.refs"
local Tag = require "obsidian.completion.sources.tags"
local NewNote = require "obsidian.completion.sources.new"

---@class obsidian.completion.Request
---@field bufnr integer
---@field cursor_after_line string
---@field cursor_before_line string
---@field line integer 0-indexed line number
---@field character integer 0-indexed byte offset into the line (utf-8)

---@param params lsp.CompletionParams
---@return obsidian.completion.Request
local function build_request(params)
  local uri = params.textDocument.uri
  local bufnr = vim.uri_to_bufnr(uri)

  -- LSP position is 0-indexed line, 0-indexed character
  local line = params.position.line
  local character = params.position.character

  -- Fetch the full line text from the buffer.
  local lines = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)
  local line_text = lines[1] or ""

  local cursor_before_line = line_text:sub(1, character)
  local cursor_after_line = line_text:sub(character + 1)

  return {
    bufnr = bufnr,
    cursor_before_line = cursor_before_line,
    cursor_after_line = cursor_after_line,
    line = line,
    character = character,
  }
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

  -- Collect results from up to 3 sources and merge before calling the LSP callback.
  -- IMPORTANT: all pending counts must be set before starting any source, because
  -- sources that can't complete call back synchronously, which would fire the final
  -- callback before remaining sources are even registered.
  local pending = 2 -- refs + tags always run
  if Obsidian.opts.completion.create_new then
    pending = pending + 1
  end

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
  Ref.process_completion(on_source_done, request)

  -- Tags source.
  Tag.process_completion(on_source_done, request)

  -- New note source (only if configured).
  if Obsidian.opts.completion.create_new then
    NewNote.process_completion(on_source_done, request)
  end
end
