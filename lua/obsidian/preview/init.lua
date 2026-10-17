local Range = require "obsidian.range"

local M = {}
local MAX_PREVIEW_BYTES = 1024 * 1024
local MAX_DIRECTORY_ENTRIES = 200
local preview_generation = 0
local owned_buffers = {}

---@param path string
---@return integer?
local function loaded_buffer(path)
  local normalized = vim.fs.normalize(path)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) or ""
    if vim.api.nvim_buf_is_loaded(bufnr) and name ~= "" and vim.fs.normalize(name) == normalized then
      return bufnr
    end
  end
end

local function scratch(lines, filetype)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  if filetype then
    vim.bo[buf].filetype = filetype
  end
  owned_buffers[buf] = true
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      owned_buffers[buf] = nil
    end,
  })
  return buf
end

---@param lines string[]
---@param filetype string|?
---@return obsidian.ui_select_preview_spec
M.text = function(lines, filetype)
  preview_generation = preview_generation + 1
  local buf = scratch(lines, filetype)
  vim.b[buf].obsidian_preview_generation = preview_generation
  return { buf = buf }
end

---Dispose preview scratch buffers that were allocated but never displayed.
---Adapters call this after closing their picker; displayed buffers are normally wiped by `bufhidden`.
M.cleanup_unshown = function()
  vim.schedule(function()
    vim.schedule(function()
      for buf in pairs(owned_buffers) do
        if vim.api.nvim_buf_is_valid(buf) then
          local displayed = false
          for _, winid in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_buf(winid) == buf then
              displayed = true
              break
            end
          end
          if not displayed then
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
          end
        else
          owned_buffers[buf] = nil
        end
      end
    end)
  end)
end

---@param spec obsidian.ui_select_preview_spec
---@return boolean
M.is_current = function(spec)
  return vim.api.nvim_buf_is_valid(spec.buf) and vim.b[spec.buf].obsidian_preview_generation == preview_generation
end

---@param spec obsidian.ui_select_preview_spec
---@param lines string[]
---@param filetype string|?
---@param pos [integer, integer]? One-based row, zero-based byte column.
---@param pos_end [integer, integer]? Half-open range end.
---@return boolean
M.update = function(spec, lines, filetype, pos, pos_end)
  if not M.is_current(spec) then
    return false
  end
  vim.bo[spec.buf].modifiable = true
  vim.api.nvim_buf_set_lines(spec.buf, 0, -1, false, lines)
  vim.bo[spec.buf].modifiable = false
  if filetype then
    vim.bo[spec.buf].filetype = filetype
  end
  spec.pos = pos
  spec.pos_end = pos_end

  local picker_util = require "obsidian.picker.util"
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(winid) == spec.buf then
      picker_util.show_preview_spec(winid, spec)
    end
  end
  return true
end

---@param path string|obsidian.Path
---@param opts { max_bytes: integer? }|?
---@return string[] lines
---@return string? filetype
M.read_path = function(path, opts)
  opts = opts or {}
  path = tostring(path)
  local bufnr = loaded_buffer(path)
  if bufnr then
    return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), vim.bo[bufnr].filetype
  end

  local stat = vim.uv.fs_stat(path)
  if not stat then
    return { "Preview unavailable: file does not exist", path }, vim.filetype.match { filename = path }
  end
  if stat.type == "directory" then
    local entries = {}
    local ok = pcall(function()
      for name, kind in vim.fs.dir(path) do
        entries[#entries + 1] = name .. (kind == "directory" and "/" or "")
        if #entries >= MAX_DIRECTORY_ENTRIES then
          break
        end
      end
    end)
    if not ok then
      return { "Preview unavailable: directory is unreadable", path }
    end
    table.sort(entries)
    if #entries == MAX_DIRECTORY_ENTRIES then
      entries[#entries + 1] = "… (directory preview truncated)"
    end
    return entries, "directory"
  end
  if stat.type ~= "file" then
    return { "Preview unavailable: unsupported file type", path }
  end

  local max_bytes = opts.max_bytes or MAX_PREVIEW_BYTES
  if stat.size > max_bytes then
    return { ("Preview unavailable: file exceeds %d bytes"):format(max_bytes), path }
  end
  local fd = vim.uv.fs_open(path, "r", 438)
  if not fd then
    return { "Preview unavailable: file is unreadable", path }
  end
  local content = vim.uv.fs_read(fd, max_bytes + 1, 0)
  vim.uv.fs_close(fd)
  if not content then
    return { "Preview unavailable: file is unreadable", path }
  end
  if content:find("\0", 1, true) then
    return { "Preview unavailable: binary file", path }
  end
  if #content > max_bytes then
    return { ("Preview unavailable: file exceeds %d bytes"):format(max_bytes), path }
  end

  local lines = vim.split(content, "\n", { plain = true })
  if #lines > 1 and lines[#lines] == "" then
    lines[#lines] = nil
  end
  return lines, vim.filetype.match { filename = path }
end

---@param path string|obsidian.Path
---@param opts { max_bytes: integer? }|?
---@return obsidian.ui_select_preview_spec
M.path = function(path, opts)
  local lines, filetype = M.read_path(path, opts)
  return M.text(lines, filetype)
end

---@param range any
---@param lines string[]
---@param encoding lsp.PositionEncodingKind
---@return [integer, integer]?, [integer, integer]?
local function range_positions(range, lines, encoding)
  if type(range) ~= "table" then
    return nil, nil
  end
  if type(range.start_row) == "number" then
    return { range.start_row + 1, range.start_col }, { range.end_row + 1, range.end_col }
  elseif range.start and range["end"] then
    local native = Range.from_lsp(range, encoding, lines)
    return { native.start_row + 1, native.start_col }, { native.end_row + 1, native.end_col }
  end
  return nil, nil
end

---Build a file or live-buffer location preview. Byte columns remain zero-based in the returned spec.
---@param opts { path: string?, bufnr: integer?, lnum: integer?, col: integer?, end_lnum: integer?, end_col: integer?, range: any?, encoding: lsp.PositionEncodingKind?, filetype: string? }
---@return obsidian.ui_select_preview_spec
M.location = function(opts)
  local bufnr = opts.bufnr
  if (not bufnr or not vim.api.nvim_buf_is_loaded(bufnr)) and opts.path then
    bufnr = loaded_buffer(opts.path)
  end

  local spec
  local lines
  if bufnr and vim.api.nvim_buf_is_loaded(bufnr) then
    lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    spec = M.text(lines, opts.filetype or vim.bo[bufnr].filetype)
  elseif opts.path then
    spec = M.path(opts.path)
    lines = vim.api.nvim_buf_get_lines(spec.buf, 0, -1, false)
  else
    return M.text({ "Preview unavailable: no source location" }, opts.filetype)
  end

  local pos, pos_end = range_positions(opts.range, lines, opts.encoding or "utf-16")
  if not pos and opts.lnum then
    pos = { opts.lnum, opts.col and math.max(opts.col - 1, 0) or 0 }
    if opts.end_lnum then
      pos_end = { opts.end_lnum, opts.end_col and math.max(opts.end_col - 1, 0) or 0 }
    end
  end
  spec.pos = pos
  spec.pos_end = pos_end
  return spec
end

---Shared URL-content rendering seam; reuse this adapter for future hover previews.
---@param context obsidian.resolver.UrlPreviewCtx
---@return obsidian.ui_select_preview_spec
M.url = function(context)
  local resolvers = require "obsidian.resolvers"
  local fallback
  resolvers.builtin.url_preview(context, function(result)
    fallback = result
  end)
  fallback = fallback or { lines = { context.url }, filetype = "markdown" }

  preview_generation = preview_generation + 1
  local token = preview_generation
  local buf = scratch(fallback.lines, fallback.filetype)
  vim.b[buf].obsidian_preview_generation = token
  local spec = { buf = buf }

  local function valid_content(result)
    if type(result) ~= "table" or type(result.lines) ~= "table" or not vim.islist(result.lines) then
      return false
    end
    if result.filetype ~= nil and type(result.filetype) ~= "string" then
      return false
    end
    for _, line in ipairs(result.lines) do
      if type(line) ~= "string" then
        return false
      end
    end
    return true
  end

  resolvers.resolve("url_preview", context, function(result)
    if token ~= preview_generation or not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    if not valid_content(result) then
      result = fallback
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, result.lines)
    vim.bo[buf].modifiable = false
    vim.bo[buf].filetype = result.filetype or "markdown"
  end)

  return spec
end

return M
