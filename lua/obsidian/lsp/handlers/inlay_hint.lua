local completion = require "obsidian.inlay_hints.completion"
local hint_cache = require "obsidian.lsp.inlay_hint_cache"

---@param bufnr integer
---@param changedtick integer
---@return boolean
local function buffer_changed(bufnr, changedtick)
  return not vim.api.nvim_buf_is_valid(bufnr)
    or not vim.api.nvim_buf_is_loaded(bufnr)
    or vim.api.nvim_buf_get_changedtick(bufnr) ~= changedtick
end

---@param params lsp.InlayHintParams
---@param callback fun(_: any, hints: lsp.InlayHint[])
return function(params, callback)
  local uri = params and params.textDocument and params.textDocument.uri
  local bufnr = uri and vim.uri_to_bufnr(uri) or 0
  local range = params and params.range or nil
  local changedtick = vim.api.nvim_buf_get_changedtick(bufnr)

  local function cached_response()
    return vim.deepcopy(hint_cache.get(uri, bufnr, range, { allow_stale = true }) or {})
  end

  local function interrupted()
    local active = completion.observe(bufnr)
    return active or buffer_changed(bufnr, changedtick)
  end

  -- Keep the last response while built-in completion is possible at the cursor.
  -- Outside completion, changedtick-aware cache entries avoid duplicate work while
  -- still allowing hints to update as the user types.
  if interrupted() then
    callback(nil, cached_response())
    return
  end

  local cached = hint_cache.get(uri, bufnr, range)
  if cached then
    callback(nil, vim.deepcopy(cached))
    return
  end

  require("obsidian.cache").when_ready(function()
    if interrupted() then
      callback(nil, cached_response())
      return
    end

    cached = hint_cache.get(uri, bufnr, range)
    if cached then
      callback(nil, vim.deepcopy(cached))
      return
    end

    local note = require("obsidian.api").current_note(bufnr, { max_lines = vim.api.nvim_buf_line_count(bufnr) })
    if not note then
      callback(nil, {})
      return
    end

    require("obsidian.resolvers").resolve("hints", {
      bufnr = bufnr,
      note = note,
      range = range,
    }, function(hints, err)
      if interrupted() then
        callback(nil, cached_response())
        return
      end

      cached = hint_cache.get(uri, bufnr, range)
      if cached then
        callback(nil, vim.deepcopy(cached))
        return
      end

      local result = err and {} or hints or {}
      hint_cache.set(uri, bufnr, range, result)
      callback(nil, result)
    end)
  end)
end
