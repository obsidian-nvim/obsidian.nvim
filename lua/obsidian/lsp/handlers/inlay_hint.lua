local completion = require "obsidian.inlay_hints.completion"
local hint_cache = require "obsidian.lsp.inlay_hint_cache"

---@type table<string, fun(_: any, hints: lsp.InlayHint[])[]>
local pending = {}

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

    local cache_generation = require("obsidian.cache").generation()
    local workspace_root = Obsidian and Obsidian.dir and tostring(Obsidian.dir) or ""
    local pending_key = table.concat({
      workspace_root,
      uri or tostring(bufnr),
      vim.inspect(range),
      tostring(changedtick),
      tostring(cache_generation),
    }, ":")
    if pending[pending_key] then
      pending[pending_key][#pending[pending_key] + 1] = callback
      return
    end
    pending[pending_key] = { callback }

    local function finish(result)
      local callbacks = pending[pending_key] or {}
      pending[pending_key] = nil
      for _, waiting_callback in ipairs(callbacks) do
        waiting_callback(nil, vim.deepcopy(result))
      end
    end

    require("obsidian.resolvers").resolve("hints", {
      bufnr = bufnr,
      note = note,
      range = range,
    }, function(hints, err)
      if interrupted() then
        finish(cached_response())
        return
      end

      cached = hint_cache.get(uri, bufnr, range)
      if cached then
        finish(cached)
        return
      end

      if
        cache_generation ~= require("obsidian.cache").generation()
        or workspace_root ~= (Obsidian and Obsidian.dir and tostring(Obsidian.dir) or "")
      then
        finish(cached_response())
        return
      end

      local result = err and {} or hints or {}
      hint_cache.set(uri, bufnr, range, result)
      finish(result)
    end)
  end)
end
