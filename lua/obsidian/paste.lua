---Smart paste: convert clipboard content to markdown and handle URLs and
---file paths pasted (or drag-and-dropped) into obsidian buffers.
---
---`M.paste` / `M.paste_url` are the manual primitives (exported via
---`obsidian.api`), `M.attach` installs the automatic `vim.paste` handler,
---guarded by `vim.g.obsidian_auto_paste`.
local log = require "obsidian.log"
local util = require "obsidian.util"

local M = {}

------------------------
---- paste location ----
------------------------

local paste_ns = vim.api.nvim_create_namespace "obsidian.paste"

---@param line string
---@param col integer 0-indexed byte offset of the cursor character
---@return integer col 0-indexed byte offset just past that character
local function char_end_col(line, col)
  local byte = line:byte(col + 1)
  if not byte then
    return #line
  end
  local len = 1
  if byte >= 240 then -- 11110xxx: 4-byte char
    len = 4
  elseif byte >= 224 then -- 1110xxxx: 3-byte char
    len = 3
  elseif byte >= 192 then -- 110xxxxx: 2-byte char
    len = 2
  end
  return math.min(col + len, #line)
end

---@class obsidian.api.PasteLocation
---@field bufnr integer
---@field extmark integer tracks the insertion point through concurrent edits
---@field cursor [integer, integer] (1,0)-indexed cursor position at record time

---Record where a paste should land, so async results are inserted at the
---position the paste was initiated from, even if the cursor moves (or the
---buffer is edited) while titles and pages are being fetched.
---
---@return obsidian.api.PasteLocation
M.record_location = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ""
  -- insert after the cursor character, like `p`
  local insert_col = #line == 0 and 0 or char_end_col(line, col)
  local extmark = vim.api.nvim_buf_set_extmark(bufnr, paste_ns, row - 1, insert_col, {})
  return { bufnr = bufnr, extmark = extmark, cursor = { row, col } }
end

---Discard a recorded paste location without inserting anything.
---
---@param loc obsidian.api.PasteLocation|?
M.discard_location = function(loc)
  if loc and vim.api.nvim_buf_is_valid(loc.bufnr) then
    vim.api.nvim_buf_del_extmark(loc.bufnr, paste_ns, loc.extmark)
  end
end

---Insert markdown at a recorded paste location: single lines go inline at the
---recorded column, multi-line content is inserted below the recorded line.
---
---@param markdown string
---@param loc obsidian.api.PasteLocation
local function put_markdown(markdown, loc)
  if not vim.api.nvim_buf_is_valid(loc.bufnr) then
    return
  end

  local mark = vim.api.nvim_buf_get_extmark_by_id(loc.bufnr, paste_ns, loc.extmark, {})
  M.discard_location(loc)
  if not mark or #mark == 0 then
    return
  end
  local row, col = mark[1], mark[2]

  local lines = vim.split(markdown, "\n")
  local end_row, end_col
  if #lines == 1 then
    local ok = pcall(vim.api.nvim_buf_set_text, loc.bufnr, row, col, row, col, lines)
    if not ok then
      return log.warn "Paste target changed before the content was ready"
    end
    end_row, end_col = row, col + #lines[1]
  else
    local ok = pcall(vim.api.nvim_buf_set_lines, loc.bufnr, row + 1, row + 1, false, lines)
    if not ok then
      return log.warn "Paste target changed before the content was ready"
    end
    end_row, end_col = row + #lines, #lines[#lines]
  end

  -- follow the paste, but only if the user hasn't moved away in the meantime
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(win) == loc.bufnr then
    local cur = vim.api.nvim_win_get_cursor(win)
    if cur[1] == loc.cursor[1] and cur[2] == loc.cursor[2] then
      pcall(vim.api.nvim_win_set_cursor, win, { end_row + 1, math.max(end_col - 1, 0) })
    end
  end
end

----------------------------
---- manual paste (api) ----
----------------------------

---Whether a string is a single bare http(s) URL.
---
---@param text string|?
---@return string|? url the trimmed URL
M.bare_url = function(text)
  if not text then
    return nil
  end
  local trimmed = vim.trim(text)
  return trimmed:match "^https?://%S+$"
end

---Paste a URL in a given form.
---
---@param url string
---@param url_as "link"|"content"|"raw"|? defaults to "link"
---@param opts { backend: obsidian.html.Backend|?, location: obsidian.api.PasteLocation|? }|?
---@return any job
M.paste_url = function(url, url_as, opts)
  opts = opts or {}
  url_as = url_as or "link"
  local loc = opts.location or M.record_location()

  if url_as == "raw" then
    put_markdown(url, loc)
    return
  end

  local weblink = require "obsidian.weblink"

  if url_as == "link" then
    return weblink.title_from_url_async(
      url,
      nil,
      vim.schedule_wrap(function(title)
        put_markdown(weblink.format_markdown_link(url, title), loc)
      end)
    )
  end

  -- url_as == "content": fetch the page and paste its body as markdown
  return weblink.fetch_html_async(url, nil, function(body, err)
    if not body then
      vim.schedule(function()
        M.discard_location(loc)
      end)
      return log.err("Failed to fetch '%s': %s", url, err)
    end

    weblink.html_to_markdown_async(
      body,
      { mode = "fragment", backend = opts.backend, url = url },
      vim.schedule_wrap(function(markdown, convert_err)
        if not markdown then
          M.discard_location(loc)
          return log.err("Failed to convert '%s' to markdown: %s", url, convert_err)
        end
        put_markdown(markdown, loc)
      end)
    )
  end)
end

---@class obsidian.api.PasteOpts
---
---What to paste from the clipboard, defaults to "auto":
---html content when available, else a bare URL, else plain text.
---@field kind "auto"|"html"|"url"|"text"|?
---
---How to paste a bare URL, defaults to "link".
---@field url_as "link"|"content"|"raw"|?
---
---HTML conversion backend override, see `Obsidian.opts.html.backend`.
---@field backend obsidian.html.Backend|?
---
---Where to insert the result, defaults to the cursor position at call time.
---@field location obsidian.api.PasteLocation|?

---Smart paste: convert the system clipboard to markdown and insert it at the cursor.
---
---The insertion point is recorded up front, so the cursor is free to move
---while content is converted or fetched.
---
---Non-interactive; see `actions.paste` for the interactive version.
---
---@param opts obsidian.api.PasteOpts|?
---@return any job
M.paste = function(opts)
  opts = opts or {}
  local clipboard = require "obsidian.clipboard"

  local kind = opts.kind or "auto"
  local text = clipboard.get_text()

  if kind == "auto" then
    if clipboard.has_html() then
      kind = "html"
    elseif M.bare_url(text) then
      kind = "url"
    else
      kind = "text"
    end
  end

  if kind == "url" then
    local url = M.bare_url(text)
    if not url then
      return log.warn "No URL in clipboard"
    end
    return M.paste_url(url, opts.url_as, { backend = opts.backend, location = opts.location })
  end

  local loc = opts.location or M.record_location()

  if kind == "html" then
    local content = clipboard.get_html()
    if not content then
      M.discard_location(loc)
      return log.warn "No HTML content in clipboard"
    end

    return require("obsidian.html").to_markdown_async(
      content,
      { mode = "fragment", backend = opts.backend },
      vim.schedule_wrap(function(markdown, err)
        if not markdown then
          M.discard_location(loc)
          return log.err("Failed to convert clipboard HTML to markdown: %s", err)
        end
        put_markdown(markdown, loc)
      end)
    )
  else
    if not text then
      M.discard_location(loc)
      return log.warn "Clipboard is empty"
    end
    put_markdown(text, loc)
  end
end

--------------------------------------------
---- automatic paste (vim.paste handler) ----
--------------------------------------------

---Unescape shell quoting/escapes terminals apply to drag-and-dropped paths:
---  /a/b/My\ Memo.pdf -> /a/b/My Memo.pdf
---@param s string
---@return string
local function unescape_shell_path(s)
  s = vim.trim(s)
  s = s:gsub('^"(.*)"$', "%1")
  s = s:gsub("^'(.*)'$", "%1")
  -- turn "\x" into "x" (covers "\ " "\(" "\[" etc.)
  s = s:gsub("\\(.)", "%1")
  return s
end

---Heuristic: does `s` look like a filesystem path?
---@param s string
---@return boolean
local function looks_like_path(s)
  if s == "" or s:match "^%a[%w+.-]*://" or s:match "^mailto:" then
    return false
  end

  -- unix absolute or home
  if s:sub(1, 1) == "/" or s:sub(1, 2) == "~/" then
    return true
  end

  -- windows drive: C:\foo or C:/foo
  if s:match "^[A-Za-z]:[\\/].+" then
    return true
  end

  return false
end

---Ask how to handle a local file and insert the resulting link.
---
---@param path string
---@param loc obsidian.api.PasteLocation
---@return boolean handled
local function handle_path(path, loc)
  local api = require "obsidian.api"
  local attachment = require "obsidian.attachment"

  local choice = api.confirm(("How to handle '%s'?"):format(vim.fs.basename(path)), "&Attach\n&Embed\n&Link")

  local link
  if choice == "Link" then
    -- link to the file in place, without copying it into the vault
    link = ("[%s](file://%s)"):format(vim.fs.basename(path), util.urlencode(path, { keep_path_sep = true }))
  elseif choice == "Attach" or choice == "Embed" then
    local dst = attachment.add(path, { insert = false, bufnr = loc.bufnr })
    if not dst then -- attachment.add already logged the error
      M.discard_location(loc)
      return true
    end
    link = attachment.format_link(dst)
    if choice == "Attach" then
      link = (link:gsub("^!", ""))
    end
  else
    M.discard_location(loc)
    log.info "Aborted"
    return true
  end

  put_markdown(link, loc)
  return true
end

---Handle a single pasted (or drag-and-dropped) line if it is a URL or a local
---file, returning true when it was consumed.
---@param line string
---@return boolean handled
local function smart_paste_line(line)
  line = unescape_shell_path(line)

  if vim.startswith(line, "file://") then
    local ok, fname = pcall(vim.uri_to_fname, line)
    if not ok then
      return false
    end
    line = fname
  end

  if M.bare_url(line) then
    if require("obsidian.attachment").is_attachment_path(line) then
      -- remote attachment (image, pdf, ...): download into the vault
      require("obsidian.actions").add_attachment(line, { insert = true })
    else
      require("obsidian.actions").paste_url(line)
    end
    return true
  end

  if looks_like_path(line) and vim.uv.fs_stat(vim.fs.normalize(line)) then
    return handle_path(vim.fs.normalize(line), M.record_location())
  end

  return false
end

---@return boolean
local function should_intercept()
  return vim.g.obsidian_auto_paste ~= false and vim.b.obsidian_buffer == true and vim.fn.mode():sub(1, 1) ~= "c"
end

local attached = false

---Install the automatic paste handler by wrapping `vim.paste` (once).
---
---Called when an obsidian buffer attaches, so content drag-and-dropped or
---pasted (e.g. <C-S-V>) into obsidian buffers is handled smartly: URLs become
---markdown links (or page content) and file paths become attachments.
---
---Guarded by `vim.g.obsidian_auto_paste`; set it to false (before or after
---setup) to disable.
---
---@param _bufnr integer|? unused, the handler checks `vim.b.obsidian_buffer` at paste time
M.attach = function(_bufnr)
  if attached or vim.g.obsidian_auto_paste == false then
    return
  end
  attached = true

  vim.paste = (function(overridden)
    ---@type string[]|? accumulated lines of an in-flight streamed paste
    local pending

    ---@param lines string[]
    ---@param phase integer
    return function(lines, phase)
      -- streamed paste in progress: keep accumulating
      if pending then
        pending[#pending] = pending[#pending] .. (lines[1] or "")
        vim.list_extend(pending, lines, 2)
        if phase ~= 3 then
          return true
        end
        local complete = pending
        pending = nil
        if #complete == 1 and should_intercept() and smart_paste_line(complete[1]) then
          return true
        end
        return overridden(complete, -1)
      end

      if not should_intercept() then
        return overridden(lines, phase)
      end

      -- start of a streamed paste (terminals chunk large pastes): accumulate
      -- and decide once complete
      if phase == 1 then
        pending = vim.deepcopy(lines)
        return true
      end

      if #lines == 1 and smart_paste_line(lines[1]) then
        return true
      end

      return overridden(lines, phase)
    end
  end)(vim.paste)
end

return M
