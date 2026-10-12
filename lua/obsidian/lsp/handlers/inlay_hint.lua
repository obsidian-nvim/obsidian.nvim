local hint_cache = require "obsidian.lsp.inlay_hint_cache"

---@return boolean
local function in_insert_mode()
  local ok, mode = pcall(vim.fn.mode, 1)
  return ok and type(mode) == "string" and mode:sub(1, 1) == "i"
end

---@param params lsp.InlayHintParams
---@param callback fun(_: any, hints: lsp.InlayHint[])
return function(params, callback)
  local uri = params and params.textDocument and params.textDocument.uri
  local bufnr = uri and vim.uri_to_bufnr(uri) or 0
  local range = params and params.range or nil
  local cached = hint_cache.get(uri, bufnr, range)

  -- Neovim requests inlay hints on every textDocument/didChange. Keep the last
  -- result until an explicit refresh (save or InsertLeave), avoiding repeated
  -- parsing and vault-wide symbol searches while editing.
  if in_insert_mode() or cached then
    callback(nil, vim.deepcopy(cached or {}))
    return
  end

  require("obsidian.cache").when_ready(function()
    cached = hint_cache.get(uri, bufnr, range)
    if in_insert_mode() or cached then
      callback(nil, vim.deepcopy(cached or {}))
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
      cached = hint_cache.get(uri, bufnr, range)
      if in_insert_mode() or cached then
        callback(nil, vim.deepcopy(cached or {}))
        return
      end

      local result = err and {} or hints or {}
      hint_cache.set(uri, bufnr, range, result)
      callback(nil, result)
    end)
  end)
end
