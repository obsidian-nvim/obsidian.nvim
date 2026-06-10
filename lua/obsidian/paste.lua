---Smart paste: convert clipboard content to markdown and handle URLs,
---images, and file paths pasted (or drag-and-dropped) into obsidian buffers.
---
---`M.paste` / `M.paste_url` are the manual primitives (exported via
---`obsidian.api`), `M.attach` installs the automatic `vim.paste` handler,
---guarded by `vim.g.obsidian_auto_paste`.
local Path = require "obsidian.path"
local log = require "obsidian.log"
local util = require "obsidian.util"
local api = require "obsidian.api"

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
local record_location = function()
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
local discard_location = function(loc)
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
  discard_location(loc)
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
---@param url_as "link"|"raw"|?
---@param opts { backend: obsidian.html.Backend|?, location: obsidian.api.PasteLocation|? }|?
---@return any job
local _paste_url = function(url, url_as, opts)
  opts = opts or {}
  url_as = url_as or "link"
  local loc = opts.location or record_location()

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
end

---Interactively paste a URL: ask how to insert it before delegating to `api.paste_url`.
---
---@param url string
---@param opts { backend: obsidian.html.Backend|?, location: obsidian.api.PasteLocation|? }|?
local paste_url = function(url, opts)
  opts = opts or {}
  local location = opts.location or record_location()

  local choice = api.confirm "Fetch link title?"

  if choice == "Yes" then
    _paste_url(url, "link", { backend = opts.backend, location = location })
  elseif choice == "No" then
    _paste_url(url, "raw", { backend = opts.backend, location = location })
  else
    discard_location(location)
    log.info "Aborted"
  end
end

---------------------
---- image paste ----
---------------------

---@alias obsidian.paste.ImageType "png"|"jpeg"|"avif"|"webp"|"bmp"|"gif"

local img_types = {
  ["image/jpeg"] = "jpeg",
  ["image/png"] = "png",
  ["image/avif"] = "avif",
  ["image/webp"] = "webp",
  ["image/bmp"] = "bmp",
  ["image/gif"] = "gif",
}

-- Image pasting adapted from https://github.com/ekickx/clipboard-image.nvim

---@param this_os OSType
---@return string|?
local function get_clip_check_command(this_os)
  local check_cmd
  if this_os == api.OSType.Linux or this_os == api.OSType.FreeBSD then
    local display_server = os.getenv "XDG_SESSION_TYPE"
    if display_server == "x11" or display_server == "tty" then
      check_cmd = "xclip -selection clipboard -o -t TARGETS"
    elseif display_server == "wayland" then
      check_cmd = "wl-paste --list-types"
    end
  elseif this_os == api.OSType.Darwin then
    check_cmd = "pngpaste -b 2>&1"
  elseif this_os == api.OSType.Windows or this_os == api.OSType.Wsl then
    check_cmd = 'powershell.exe "Get-Clipboard -Format Image"'
  end
  return check_cmd
end

---@param content string[]
---@return obsidian.paste.ImageType|?
local function get_image_type(content)
  for _, line in ipairs(content) do
    if img_types[line] ~= nil then
      return img_types[line]
    end
  end
  return nil
end

---Get the type of image on the clipboard.
---
---@param opts { convert_uri: boolean|? }|?
---@return obsidian.paste.ImageType|?
function M.get_clipboard_img_type(opts)
  opts = opts or {}
  local this_os = api.get_os()
  local check_cmd = get_clip_check_command(this_os)
  if not check_cmd then
    error("image saving not implemented for OS '" .. this_os .. "'")
  end
  local result_string = vim.fn.system(check_cmd)
  if vim.v.shell_error ~= 0 then
    return nil
  end
  local content = vim.split(result_string, "\n")

  -- See: [Data URI scheme](https://en.wikipedia.org/wiki/Data_URI_scheme)
  if this_os == api.OSType.Linux or this_os == api.OSType.FreeBSD then
    if vim.tbl_contains(content, "text/uri-list") then
      if opts.convert_uri == false then
        return nil
      end
      local success =
        os.execute "wl-paste --type text/uri-list | sed 's|file://||' | head -n1 | tr -d '[:space:]' | xargs -I{} sh -c 'wl-copy < \"$1\"' _ {}"
      if success == 0 then
        -- Re-check for image type after potential conversion
        result_string = vim.fn.system(check_cmd)
        content = vim.split(result_string, "\n")
        return get_image_type(content)
      end
    else
      return get_image_type(content)
    end

  -- Code for non-Linux Operating systems (only supports png)
  elseif this_os == api.OSType.Darwin then
    local is_img = string.sub(content[1], 1, 9) == "iVBORw0KG" -- Magic png number in base64
    if is_img then
      return "png"
    end
  elseif this_os == api.OSType.Windows or this_os == api.OSType.Wsl then
    if vim.trim(result_string) ~= "" then
      return "png"
    end
  else
    error("image saving not implemented for OS '" .. this_os .. "'")
  end
  return nil
end

---TODO: refactor Windows with run_job?

---Save image from clipboard to `path`.
---@param path string
---@param img_type obsidian.paste.ImageType
---@return boolean|? result
local function save_clipboard_image(path, img_type)
  local this_os = api.get_os()

  if this_os == api.OSType.Linux or this_os == api.OSType.FreeBSD then
    local mime_type = "image/" .. img_type
    local cmd
    local display_server = os.getenv "XDG_SESSION_TYPE"
    if display_server == "x11" or display_server == "tty" then
      cmd = string.format("xclip -selection clipboard -t %s -o > '%s'", mime_type, path)
      return vim.system({ "bash", "-c", cmd }):wait() ~= 0
    elseif display_server == "wayland" then
      cmd = string.format("wl-paste --no-newline --type %s > %s", mime_type, vim.fn.shellescape(path))
      return vim.system({ "bash", "-c", cmd }):wait() ~= 0
    end
  elseif this_os == api.OSType.Windows or this_os == api.OSType.Wsl then
    local cmd = 'powershell.exe -c "'
      .. string.format("(get-clipboard -format image).save('%s', 'png')", string.gsub(path, "/", "\\"))
      .. '"'
    local ret = os.execute(cmd) -- TODO:
    return ret
  elseif this_os == api.OSType.Darwin then
    return vim.system({ "pngpaste", path }):wait() ~= 0
  else
    error("image saving not implemented for OS '" .. this_os .. "'")
  end
end

---Paste an image from the clipboard to `path` and insert its markdown link.
---
---Kept as the compatibility primitive for `obsidian.img_paste.paste()` and
---`:Obsidian paste_img`, but implemented with the same location-aware paste
---machinery as general paste.
---
---@param path string|obsidian.Path image_path The absolute path to the image file.
---@param img_type obsidian.paste.ImageType
---@param opts { location: obsidian.api.PasteLocation|? }|?
M.paste_image = function(path, img_type, opts)
  opts = opts or {}
  local loc = opts.location or record_location()

  if util.contains_invalid_characters(path) then
    log.warn "Links will not work with file names containing any of these characters in Obsidian: # ^ [ ] |"
  end

  path = Path.new(path)

  -- If there is no suffix provided, append it.
  if not path.suffix then
    ---@diagnostic disable-next-line: cast-local-type
    path = path:with_suffix("." .. img_type)

  -- If user appends their own suffix, check if it is valid based on img_type.
  elseif not (path.suffix == "." .. img_type or (img_type == "jpeg" and path.suffix == ".jpg")) then
    discard_location(loc)
    local expected_suffix = (img_type == "jpeg") and ".jpeg' or '.jpg" or "." .. img_type
    return log.err("invalid suffix for image name '%s', must be '%s'", path.suffix, expected_suffix)
  end

  if Obsidian.opts.attachments.confirm_img_paste then
    local choice = api.confirm("Saving image to '" .. tostring(path) .. "'. Do you want to continue?")
    if choice ~= "Yes" then
      discard_location(loc)
      return log.warn "Paste aborted"
    end
  end

  -- Ensure parent directory exists.
  assert(path:parent()):mkdir { exist_ok = true, parents = true }

  -- Paste image.
  local result = save_clipboard_image(tostring(path), img_type)
  if result == false then
    discard_location(loc)
    log.err "Failed to save image"
    return
  end

  put_markdown(Obsidian.opts.attachments.img_text_func(path), loc)
end

---@param opts { location: obsidian.api.PasteLocation|?, path: string|obsidian.Path|?, image_path: string|obsidian.Path|?, name: string|?, image_name: string|?, img_type: obsidian.paste.ImageType|?, image_type: obsidian.paste.ImageType|? }|?
local function paste_image_from_clipboard(opts)
  opts = opts or {}
  local loc = opts.location or record_location()
  local img_type = opts.img_type or opts.image_type or M.get_clipboard_img_type()
  if not img_type then
    discard_location(loc)
    return log.err "There is no image data in the clipboard"
  end

  local path = opts.path or opts.image_path
  if not path then
    local fname = opts.name or opts.image_name
    if not fname or fname == "" then
      local default_name = Obsidian.opts.attachments.img_name_func()
      if default_name and not Obsidian.opts.attachments.confirm_img_paste then
        fname = default_name
      else
        local input = api.input("Enter file name: ", { default = default_name, completion = "file" })
        if not input then
          discard_location(loc)
          return log.warn "Paste aborted"
        end
        fname = input
      end
    end
    path = api.resolve_attachment_path(vim.trim(fname), loc.bufnr)
  end

  return M.paste_image(path, img_type, { location = loc })
end

---@class obsidian.api.PasteOpts
---
---What to paste from the clipboard, defaults to "auto":
---image content when available, else html content when available, else a bare
---URL, else plain text.
---@field kind "auto"|"html"|"url"|"text"|"image"|?
---
---HTML conversion backend override, see `Obsidian.opts.html.backend`.
---@field backend obsidian.html.Backend|?
---
---For bare URLs, paste as a markdown link or raw URL. Defaults to prompting.
---@field url_as "link"|"raw"|?
---
---Image destination override for `kind = "image"`; otherwise the user is
---prompted (or `attachments.img_name_func()` is used when confirmation is off).
---@field path string|obsidian.Path|?
---@field image_path string|obsidian.Path|?
---@field name string|?
---@field image_name string|?
---@field img_type obsidian.paste.ImageType|?
---@field image_type obsidian.paste.ImageType|?
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

  local kind = opts.kind
  local text = clipboard.get_text()
  local loc = opts.location or record_location()
  local img_type = opts.img_type or opts.image_type

  if opts.kind == nil or opts.kind == "auto" then
    local ok, detected_img_type = pcall(M.get_clipboard_img_type, { convert_uri = false })
    if ok and detected_img_type then
      kind = "image"
      img_type = detected_img_type
    elseif clipboard.has_html() then
      kind = "html"
    elseif M.bare_url(text) then
      kind = "url"
    else
      kind = "text"
    end
  end

  if kind == "image" then
    opts = vim.tbl_extend("force", opts, { location = loc, img_type = img_type })
    return paste_image_from_clipboard(opts)
  end

  if kind == "url" then
    local url = M.bare_url(text)
    if not url then
      return log.warn "No URL in clipboard"
    end
    if opts.url_as then
      return _paste_url(url, opts.url_as, { backend = opts.backend, location = loc })
    end
    return paste_url(url, { backend = opts.backend, location = loc })
  end

  if kind == "html" then
    local content = clipboard.get_html()
    if not content then
      discard_location(loc)
      return log.warn "No HTML content in clipboard"
    end

    return require("obsidian.html").to_markdown_async(
      content,
      { mode = "fragment", backend = opts.backend },
      vim.schedule_wrap(function(markdown, err)
        if not markdown then
          discard_location(loc)
          return log.err("Failed to convert clipboard HTML to markdown: %s", err)
        end
        put_markdown(markdown, loc)
      end)
    )
  else
    if not text then
      discard_location(loc)
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
  local attachment = require "obsidian.attachment"

  local choice = api.confirm(("How to handle '%s'?"):format(vim.fs.basename(path)), "&Attach\n&Embed\n&Link")

  local link
  if choice == "Link" then
    -- link to the file in place, without copying it into the vault
    link = ("[%s](file://%s)"):format(vim.fs.basename(path), util.urlencode(path, { keep_path_sep = true }))
  elseif choice == "Attach" or choice == "Embed" then
    local dst = attachment.add(path, { insert = false, bufnr = loc.bufnr })
    if not dst then -- attachment.add already logged the error
      discard_location(loc)
      return true
    end
    link = attachment.format_link(dst)
    if choice == "Attach" then
      link = (link:gsub("^!", ""))
    end
  else
    discard_location(loc)
    log.info "Aborted"
    return true
  end

  put_markdown(link, loc)
  return true
end

---@param text string
---@return string
local function normalize_newlines(text)
  return (text:gsub("\r\n", "\n"):gsub("\r", "\n"))
end

---@param a string
---@param b string
---@return boolean
local function same_paste_text(a, b)
  a = normalize_newlines(a)
  b = normalize_newlines(b)
  return a == b or (vim.endswith(a, "\n") and a:sub(1, -2) == b) or (vim.endswith(b, "\n") and b:sub(1, -2) == a)
end

---Handle pasted clipboard HTML using the same conversion path as `M.paste`.
---@param lines string[]
---@return boolean handled
local function smart_paste_clipboard_html(lines)
  local clipboard = require "obsidian.clipboard"
  local text = clipboard.get_text()
  if not text or not same_paste_text(text, table.concat(lines, "\n")) or not clipboard.has_html() then
    return false
  end

  M.paste { kind = "html", location = record_location() }
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
    paste_url(line, { location = record_location() })
    return true
  end

  if looks_like_path(line) and vim.uv.fs_stat(vim.fs.normalize(line)) then
    return handle_path(vim.fs.normalize(line), record_location())
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
        if should_intercept() then
          if smart_paste_clipboard_html(complete) then
            return true
          end
          if #complete == 1 and smart_paste_line(complete[1]) then
            return true
          end
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

      if smart_paste_clipboard_html(lines) then
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
