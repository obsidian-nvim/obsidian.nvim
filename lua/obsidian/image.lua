local util = require "obsidian.util"
local attachment = require "obsidian.attachment"

local M = {}

local ns = vim.api.nvim_create_namespace "obsidian.image"

---@alias obsidian.image.Placement "inline"|"hover"|"fixed"

---@class obsidian.image.Opts
---@field placement? obsidian.image.Placement
---@field width? integer
---@field height? integer
---@field max_width? integer
---@field max_height? integer
---@field zindex? integer
---@field pad? integer
---@field conceal? boolean|string
---@field relative? "buffer"|"ui"
---@field formats? string[]
---@field visible_only? boolean
---@field margin? integer
---@field debounce? integer
---@field enabled? boolean

---@class obsidian.image.Match
---@field src string
---@field path string
---@field row integer 0-indexed
---@field col integer 0-indexed
---@field end_col integer 0-indexed, exclusive
---@field key string
---@field win integer
---@field pad integer
---@field width_px? integer
---@field height_px? integer

---@class obsidian.image.Rendered
---@field id integer
---@field buf integer
---@field opts table
---@field anchor? integer
---@field spacer? integer

---@class obsidian.image.State
---@field buf integer
---@field group integer
---@field opts obsidian.image.Opts
---@field rendered table<string, obsidian.image.Rendered>
---@field timer uv.uv_timer_t?
---@field force? boolean
---@field resized table<string, obsidian.image.Size>

---@type table<integer, obsidian.image.State>
local states = {}

local defaults = {
  placement = "inline",
  zindex = 50,
  visible_only = true,
  margin = 10,
  debounce = 50,
  max_width = 80,
  max_height = 40,
  formats = { "png" },
  relative = "buffer",
}

---@param opts obsidian.image.Opts|?
---@return obsidian.image.Opts
local function normalize_opts(opts)
  return vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

---@param path string
---@param formats string[]
---@return boolean
local function supported_format(path, formats)
  local ext = path:match "%.([^./\\]+)$"
  return ext ~= nil and vim.list_contains(formats, ext:lower())
end

---@param spec string
---@return integer? width_px
---@return integer? height_px
local function parse_size_spec(spec)
  spec = vim.trim(spec)
  local width, height = spec:match "^(%d+)x(%d+)$"
  if width and height then
    return tonumber(width), tonumber(height)
  end

  width = spec:match "^(%d+)$"
  if width then
    return tonumber(width), nil
  end
end

---@param target string
---@return integer? width_px
---@return integer? height_px
local function parse_wiki_size(target)
  local size_spec = target:match "|([^|]+)$"
  if not size_spec then
    return nil, nil
  end
  return parse_size_spec(size_spec)
end

---@param path string
---@return boolean
local function exists(path)
  return path ~= "" and vim.uv.fs_stat(path) ~= nil
end

---@return boolean supported
function M.supported()
  if type(vim.ui) ~= "table" or type(vim.ui.img) ~= "table" or type(vim.ui.img.set) ~= "function" then
    return false
  end

  if type(vim.ui.img._supported) == "function" then
    local ok, supported = pcall(vim.ui.img._supported)
    return ok and supported == true
  end

  return true
end

---@param path string
---@return string data
local function read_file(path)
  if vim.fn.exists "*readblob" == 1 then
    local ok, data = pcall(vim.fn.readblob, path)
    if ok then
      return data
    end
  end

  local fd = assert(io.open(path, "rb"))
  local data = assert(fd:read "*a")
  fd:close()
  return data
end

---@class obsidian.image.Size
---@field width integer
---@field height integer

---@class obsidian.image.ResizeOpts
---@field step? integer Number of terminal cells to add to, or subtract from, the image's largest dimension.

---@type table<string, obsidian.image.Size>
local image_dims = {}

---@param path string
---@return obsidian.image.Size
local function png_dims(path)
  path = vim.fs.normalize(path)
  if image_dims[path] then
    return image_dims[path]
  end

  local fd = assert(io.open(path, "rb"))
  local header = assert(fd:read(24))
  fd:close()

  assert(header:sub(1, 8) == "\137PNG\r\n\26\n", "not a PNG image: " .. path)
  image_dims[path] = {
    width = header:byte(17) * 16777216 + header:byte(18) * 65536 + header:byte(19) * 256 + header:byte(20),
    height = header:byte(21) * 16777216 + header:byte(22) * 65536 + header:byte(23) * 256 + header:byte(24),
  }
  return image_dims[path]
end

---@type obsidian.image.Size?
local terminal_size

---@return obsidian.image.Size
local function terminal_cell_size()
  if terminal_size then
    return terminal_size
  end

  terminal_size = { width = 9, height = 18 }
  local ok, ffi = pcall(require, "ffi")
  if not ok then
    return terminal_size
  end

  pcall(
    ffi.cdef,
    [[
    typedef struct {
      unsigned short row;
      unsigned short col;
      unsigned short xpixel;
      unsigned short ypixel;
    } winsize;
    int ioctl(int, int, ...);
  ]]
  )

  local tiocgwinsz
  if vim.fn.has "linux" == 1 then
    tiocgwinsz = 0x5413
  elseif vim.fn.has "mac" == 1 or vim.fn.has "bsd" == 1 then
    tiocgwinsz = 0x40087468
  end
  if not tiocgwinsz then
    return terminal_size
  end

  pcall(function()
    local sz = ffi.new "winsize"
    if ffi.C.ioctl(1, tiocgwinsz, sz) == 0 and sz.col > 0 and sz.row > 0 and sz.xpixel > 0 and sz.ypixel > 0 then
      terminal_size = {
        width = sz.xpixel / sz.col,
        height = sz.ypixel / sz.row,
      }
    end
  end)

  return terminal_size
end

---@param size obsidian.image.Size
---@param bounds obsidian.image.Size
---@return obsidian.image.Size
local function fit_size(size, bounds)
  if size.width <= bounds.width and size.height <= bounds.height then
    return size
  end

  local ret = {
    width = math.min(bounds.width, size.width),
    height = math.min(bounds.height, size.height),
  }
  local scale = ret.width / ret.height
  local image_scale = size.width / size.height
  local fit_height = math.floor(ret.width / image_scale + 0.5)
  local fit_width = math.floor(ret.height * image_scale + 0.5)

  if image_scale > scale then
    ret.height = fit_height
  else
    ret.width = fit_width
  end

  return {
    width = math.max(1, math.ceil(ret.width)),
    height = math.max(1, math.ceil(ret.height)),
  }
end

---@param width_px number
---@param height_px number
---@return obsidian.image.Size
local function px_to_cells(width_px, height_px)
  local cell = terminal_cell_size()
  return {
    width = math.max(1, math.ceil(width_px / cell.width)),
    height = math.max(1, math.ceil(height_px / cell.height)),
  }
end

---@param path string
---@return obsidian.image.Size?
local function image_size_cells(path)
  local ok, dims = pcall(png_dims, path)
  if not ok then
    return nil
  end
  return px_to_cells(dims.width, dims.height)
end

---@param target string
---@return string
local function clean_target(target)
  target = vim.trim(target)
  target = target:gsub("^<(.+)>$", "%1")

  -- Drop markdown titles from `![alt](foo.png "title")`.
  local first = target:match "^(%S+)%s+['\"].-['\"]$"
  if first then
    target = first
  end

  -- Obsidian wiki embeds can be `![[image.png|300x200]]`.
  target = target:match "^([^|]+)" or target

  -- Local images don't need query/fragment components for filesystem lookup.
  target = target:gsub("#.*$", ""):gsub("%?.*$", "")
  target = target:gsub("\\ ", " ")
  return vim.uri_decode(target)
end

---@param path string
---@return boolean
local function is_absolute(path)
  return vim.startswith(path, "/") or path:match "^%a:[/\\]" ~= nil
end

---@param src string
---@param bufnr integer
---@return string?
local function resolve_path(src, bufnr)
  src = clean_target(src)
  if src == "" then
    return nil
  end

  local is_uri, scheme = util.is_uri(src)
  if is_uri then
    if scheme == "file" then
      return vim.uri_to_fname(src)
    end
    return nil
  end

  if is_absolute(src) and exists(src) then
    return src
  end

  local buf_name = vim.api.nvim_buf_get_name(bufnr)
  local buf_dir = buf_name ~= "" and vim.fs.dirname(buf_name) or vim.fn.getcwd()
  local candidates = {
    vim.fs.normalize(buf_dir .. "/" .. src),
  }

  if Obsidian and Obsidian.dir then
    candidates[#candidates + 1] = vim.fs.normalize(tostring(Obsidian.dir) .. "/" .. src)
  end

  if Obsidian and Obsidian.opts and Obsidian.opts.attachments then
    candidates[#candidates + 1] = attachment.resolve_attachment_path(src, bufnr)
  end

  for _, candidate in ipairs(candidates) do
    if exists(candidate) then
      return candidate
    end
  end
end

---@param line string
---@param row integer
---@param bufnr integer
---@param opts obsidian.image.Opts
---@param win integer|?
---@return obsidian.image.Match[]
local function find_line_images(line, row, bufnr, opts, win)
  ---@type obsidian.image.Match[]
  local ret = {}

  local function add(start_col, end_col, src, width_px, height_px)
    local path = resolve_path(src, bufnr)
    if not path or not supported_format(path, opts.formats or defaults.formats) then
      return
    end
    local key_win = opts.relative == "ui" and (win or 0) or 0
    ret[#ret + 1] = {
      src = src,
      path = path,
      row = row,
      col = start_col,
      end_col = end_col,
      key = table.concat({ key_win, row, start_col, end_col, path }, ":"),
      win = win or 0,
      pad = util.strdisplaywidth(line:sub(1, start_col)),
      width_px = width_px,
      height_px = height_px,
    }
  end

  for start_col, body, end_pos in line:gmatch "()!%[%[([^%]]+)%]%]()" do
    local width_px, height_px = parse_wiki_size(body)
    add(start_col - 1, end_pos - 1, body, width_px, height_px)
  end

  for start_col, alt, target, end_pos in line:gmatch "()!%[([^%]]*)%]%(([^%)]+)%)()" do
    local width_px, height_px = parse_size_spec(alt)
    add(start_col - 1, end_pos - 1, target, width_px, height_px)
  end

  return ret
end

---@param bufnr integer
---@return integer[]
local function visible_wins(bufnr)
  local wins = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
      wins[#wins + 1] = win
    end
  end
  return wins
end

---@param bufnr integer
---@param opts obsidian.image.Opts
---@param win integer|?
---@return integer start_row 0-indexed, inclusive
---@return integer end_row 0-indexed, exclusive
local function visible_range(bufnr, opts, win)
  if not opts.visible_only then
    return 0, vim.api.nvim_buf_line_count(bufnr)
  end

  if win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
    local start_row, end_row
    vim.api.nvim_win_call(win, function()
      start_row = vim.fn.line "w0"
      end_row = vim.fn.line "w$"
    end)
    local margin = opts.margin or 0
    return math.max(start_row - 1 - margin, 0), math.min(end_row + margin, vim.api.nvim_buf_line_count(bufnr))
  end

  return 0, 0
end

---@param state obsidian.image.State
---@return obsidian.image.Match[]
local function find_images(state)
  local wins = visible_wins(state.buf)
  if #wins == 0 then
    return {}
  end

  ---@type obsidian.image.Match[]
  local matches = {}
  local seen = {}
  for _, win in ipairs(wins) do
    local start_row, end_row = visible_range(state.buf, state.opts, win)
    local lines = vim.api.nvim_buf_get_lines(state.buf, start_row, end_row, false)
    for i, line in ipairs(lines) do
      for _, match in ipairs(find_line_images(line, start_row + i - 1, state.buf, state.opts, win)) do
        if not seen[match.key] then
          seen[match.key] = true
          matches[#matches + 1] = match
        end
      end
    end
  end
  return matches
end

local renderers = {}
M.renderers = renderers

---@param match obsidian.image.Match
---@param state obsidian.image.State
---@return obsidian.image.Size
local function image_bounds(match, state)
  local max_width = state.opts.max_width or defaults.max_width
  local max_height = state.opts.max_height or defaults.max_height

  if match.win and vim.api.nvim_win_is_valid(match.win) then
    local info = vim.fn.getwininfo(match.win)[1]
    if info then
      max_width = math.min(max_width, math.max(1, info.width - info.textoff - match.col))
    end
  end

  return {
    width = state.opts.width or max_width,
    height = state.opts.height or max_height,
  }
end

---@param match obsidian.image.Match
---@return obsidian.image.Size?
local function embed_size_cells(match)
  if not match.width_px then
    return nil
  end

  local width_px = match.width_px
  local height_px = match.height_px
  if not height_px then
    local ok, dims = pcall(png_dims, match.path)
    if not ok then
      return nil
    end
    height_px = width_px * dims.height / dims.width
  end

  return px_to_cells(width_px, height_px)
end

---@param match obsidian.image.Match
---@param state obsidian.image.State
---@return obsidian.image.Size?
local function inline_size(match, state)
  local resized = state.resized and state.resized[match.key]
  if resized then
    return resized
  end

  local embed_size = embed_size_cells(match)
  if embed_size then
    return embed_size
  end

  local size = image_size_cells(match.path)
  if size then
    return fit_size(size, image_bounds(match, state))
  end
end

---@param match obsidian.image.Match
---@param state obsidian.image.State
---@return table? opts
local function inline_ui_opts(match, state)
  if not (match.win and vim.api.nvim_win_is_valid(match.win)) then
    return nil
  end

  local pos = vim.fn.screenpos(match.win, match.row + 1, match.col + 1)
  if not pos or pos.row == 0 or pos.col == 0 then
    return nil
  end

  local resized = state.resized and state.resized[match.key]
  local embed_size = embed_size_cells(match)
  local size = inline_size(match, state)
  return {
    row = pos.row + 1,
    col = pos.col,
    width = resized and resized.width or (embed_size and embed_size.width) or state.opts.width or (size and size.width),
    height = resized and resized.height
      or (embed_size and embed_size.height)
      or state.opts.height
      or (size and size.height),
    zindex = state.opts.zindex,
  }
end

---@param match obsidian.image.Match
---@param state obsidian.image.State
---@return table? opts
function renderers.inline(match, state)
  if state.opts.relative == "ui" then
    return inline_ui_opts(match, state)
  end

  local resized = state.resized and state.resized[match.key]
  local embed_size = embed_size_cells(match)
  local size = inline_size(match, state)
  return {
    row = match.row + 1,
    col = 1,
    width = resized and resized.width or (embed_size and embed_size.width) or state.opts.width or (size and size.width),
    height = resized and resized.height
      or (embed_size and embed_size.height)
      or state.opts.height
      or (size and size.height),
    zindex = state.opts.zindex,
    relative = "buffer",
    buf = state.buf,
    pad = state.opts.pad or match.pad,
  }
end

---@param _match obsidian.image.Match
---@param _state obsidian.image.State
function renderers.hover(_match, _state)
  error "obsidian.image: hover placement is not implemented yet"
end

---@param _match obsidian.image.Match
---@param _state obsidian.image.State
function renderers.fixed(_match, _state)
  error "obsidian.image: fixed placement is not implemented yet"
end

---@param rendered obsidian.image.Rendered
local function del_rendered(rendered)
  if M.supported() and type(vim.ui.img.del) == "function" then
    pcall(vim.ui.img.del, rendered.id)
  end
  if rendered.anchor then
    pcall(vim.api.nvim_buf_del_extmark, rendered.buf, ns, rendered.anchor)
  end
  if rendered.spacer then
    pcall(vim.api.nvim_buf_del_extmark, rendered.buf, ns, rendered.spacer)
  end
end

---@param rendered obsidian.image.Rendered
---@param state obsidian.image.State
---@param match obsidian.image.Match
local function update_spacer(rendered, state, match)
  if (state.opts.placement or "inline") ~= "inline" then
    return
  end

  if rendered.opts and rendered.opts.relative == "buffer" then
    return
  end

  local height = rendered.opts and rendered.opts.height or state.opts.height
  if not height and type(vim.ui.img.get) == "function" then
    local ok, img_opts = pcall(vim.ui.img.get, rendered.id)
    if ok and img_opts then
      height = img_opts.height
    end
  end

  if type(height) ~= "number" or height <= 0 then
    return
  end

  if rendered.spacer then
    pcall(vim.api.nvim_buf_del_extmark, rendered.buf, ns, rendered.spacer)
  end

  local virt_lines = {}
  for i = 1, height do
    virt_lines[i] = { { " ", "Normal" } }
  end
  rendered.spacer = vim.api.nvim_buf_set_extmark(state.buf, ns, match.row, 0, {
    virt_lines = virt_lines,
    virt_lines_above = false,
    invalidate = true,
    undo_restore = false,
  })
end

---@param state obsidian.image.State
---@param match obsidian.image.Match
---@param rendered obsidian.image.Rendered?
---@return obsidian.image.Rendered?
local function render_match(state, match, rendered)
  local renderer = renderers[state.opts.placement or "inline"]
  if not renderer then
    error("obsidian.image: unknown placement " .. tostring(state.opts.placement))
  end

  local img_opts = renderer(match, state)
  if not img_opts then
    return nil
  end

  if rendered then
    local ok = pcall(vim.ui.img.set, rendered.id, img_opts)
    if not ok and img_opts.relative == "buffer" then
      img_opts = inline_ui_opts(match, state)
      ok = img_opts ~= nil and pcall(vim.ui.img.set, rendered.id, img_opts)
    end
    if not ok then
      return nil
    end
    rendered.opts = img_opts
    update_spacer(rendered, state, match)
    return rendered
  end

  local ok, data = pcall(read_file, match.path)
  if not ok then
    return nil
  end

  local set_ok, id = pcall(vim.ui.img.set, data, img_opts)
  if not set_ok and img_opts.relative == "buffer" then
    img_opts = inline_ui_opts(match, state)
    if img_opts ~= nil then
      set_ok, id = pcall(vim.ui.img.set, data, img_opts)
    end
  end
  if not set_ok then
    return nil
  end
  rendered = { id = id, buf = state.buf, opts = img_opts }

  if state.opts.conceal then
    local conceal = type(state.opts.conceal) == "string" and state.opts.conceal or ""
    rendered.anchor = vim.api.nvim_buf_set_extmark(state.buf, ns, match.row, match.col, {
      end_row = match.row,
      end_col = match.end_col,
      conceal = conceal,
      invalidate = true,
      undo_restore = false,
    })
  end

  update_spacer(rendered, state, match)

  return rendered
end

---@param bufnr integer
---@param force boolean|?
function M.refresh(bufnr, force)
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  local state = states[bufnr]
  if not state or not vim.api.nvim_buf_is_valid(bufnr) or not M.supported() then
    return
  end

  local next_rendered = {} ---@type table<string, obsidian.image.Rendered>
  for _, match in ipairs(find_images(state)) do
    local previous = state.rendered[match.key]
    if force and previous then
      del_rendered(previous)
      previous = nil
    end
    local rendered = render_match(state, match, previous)
    if rendered then
      next_rendered[match.key] = rendered
    end
  end

  for key, rendered in pairs(state.rendered) do
    if not next_rendered[key] then
      del_rendered(rendered)
    end
  end

  state.rendered = next_rendered
end

---@param state obsidian.image.State
---@param force boolean|?
local function schedule_refresh(state, force)
  state.force = state.force or force
  if state.timer then
    state.timer:stop()
  else
    state.timer = assert(vim.uv.new_timer())
  end
  state.timer:start(
    state.opts.debounce or 0,
    0,
    vim.schedule_wrap(function()
      local refresh_force = state.force
      state.force = false
      M.refresh(state.buf, refresh_force)
    end)
  )
end

---@param rendered obsidian.image.Rendered?
---@param state obsidian.image.State
---@param match obsidian.image.Match
---@return obsidian.image.Size?
local function rendered_size(rendered, state, match)
  local opts = rendered and rendered.opts
  if rendered and type(vim.ui.img.get) == "function" then
    local ok, img_opts = pcall(vim.ui.img.get, rendered.id)
    if ok and img_opts then
      opts = img_opts
    end
  end

  if not opts then
    local renderer = renderers[state.opts.placement or "inline"]
    opts = renderer and renderer(match, state)
  end

  if type(opts) ~= "table" then
    return nil
  end

  local width = type(opts.width) == "number" and opts.width or nil
  local height = type(opts.height) == "number" and opts.height or nil
  if not (width and height) then
    local size = image_size_cells(match.path)
    if size then
      if width then
        height = math.max(1, math.floor((width * size.height) / size.width + 0.5))
      elseif height then
        width = math.max(1, math.floor((height * size.width) / size.height + 0.5))
      else
        size = fit_size(size, image_bounds(match, state))
        width = size.width
        height = size.height
      end
    end
  end

  if not (width and height) then
    return nil
  end

  return {
    width = math.max(1, math.floor(width + 0.5)),
    height = math.max(1, math.floor(height + 0.5)),
  }
end

---@param size obsidian.image.Size
---@param delta integer
---@return obsidian.image.Size
local function resize_size(size, delta)
  local largest = math.max(size.width, size.height)
  local next_largest = math.max(1, largest + delta)
  local scale = next_largest / largest

  return {
    width = math.max(1, math.floor(size.width * scale + 0.5)),
    height = math.max(1, math.floor(size.height * scale + 0.5)),
  }
end

---Resize the image under the cursor.
---
---The cursor must be on an image link/embed. Returns `true` if the image was resized.
---@param delta integer Positive values grow the image, negative values shrink it.
---@param opts obsidian.image.ResizeOpts|?
---@param bufnr integer|?
---@return boolean
function M.resize_under_cursor(delta, opts, bufnr)
  bufnr = bufnr or 0
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  local state = states[bufnr]
  if not state or not M.supported() or delta == 0 then
    return false
  end
  state.resized = state.resized or {}

  local win = vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= bufnr then
    return false
  end

  local row, col = unpack(vim.api.nvim_win_get_cursor(win))
  local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1]
  if not line then
    return false
  end

  ---@type obsidian.image.Match?
  local cursor_match
  for _, match in ipairs(find_line_images(line, row - 1, bufnr, state.opts, win)) do
    if match.col <= col and col < match.end_col then
      cursor_match = match
      break
    end
  end
  if not cursor_match then
    return false
  end

  opts = opts or {}
  local step = math.max(1, math.floor(tonumber(opts.step) or math.abs(delta)))
  local signed_step = delta < 0 and -step or step
  local rendered = state.rendered[cursor_match.key]
  local size = rendered_size(rendered, state, cursor_match)
  if not size then
    return false
  end

  local next_size = resize_size(size, signed_step)
  if next_size.width == size.width and next_size.height == size.height then
    return false
  end

  local previous_size = state.resized[cursor_match.key]
  state.resized[cursor_match.key] = next_size
  local next_rendered = render_match(state, cursor_match, rendered)
  if next_rendered then
    state.rendered[cursor_match.key] = next_rendered
    return true
  end

  state.resized[cursor_match.key] = previous_size
  return false
end

---Make the image under the cursor bigger.
---@param opts obsidian.image.ResizeOpts|?
---@return boolean
function M.increase_size(opts)
  return M.resize_under_cursor(1, opts)
end

---Make the image under the cursor smaller.
---@param opts obsidian.image.ResizeOpts|?
---@return boolean
function M.decrease_size(opts)
  return M.resize_under_cursor(-1, opts)
end

---@param bufnr integer|?
---@param opts obsidian.image.Opts|?
function M.attach(bufnr, opts)
  bufnr = bufnr or 0
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr

  if not M.supported() then
    return
  end

  if states[bufnr] then
    M.detach(bufnr)
  end

  local state = {
    buf = bufnr,
    group = vim.api.nvim_create_augroup("obsidian.image." .. bufnr, { clear = true }),
    opts = normalize_opts(opts),
    rendered = {},
    resized = {},
  }
  states[bufnr] = state

  vim.api.nvim_create_autocmd({ "BufWinEnter", "TextChanged", "TextChangedI", "BufWritePost" }, {
    group = state.group,
    buffer = bufnr,
    callback = function()
      schedule_refresh(state)
    end,
  })

  vim.api.nvim_create_autocmd("WinScrolled", {
    group = state.group,
    callback = function()
      schedule_refresh(state)
    end,
  })

  vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
    group = state.group,
    callback = function()
      schedule_refresh(state, true)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = state.group,
    buffer = bufnr,
    callback = function()
      M.detach(bufnr)
    end,
  })

  schedule_refresh(state)
end

---@param bufnr integer|?
---@return boolean
function M.is_attached(bufnr)
  bufnr = bufnr or 0
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  return states[bufnr] ~= nil
end

---@param bufnr integer|?
function M.detach(bufnr)
  bufnr = bufnr or 0
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  local state = states[bufnr]
  if not state then
    return
  end

  if state.timer then
    state.timer:stop()
    state.timer:close()
  end

  for _, rendered in pairs(state.rendered) do
    del_rendered(rendered)
  end
  states[bufnr] = nil
  pcall(vim.api.nvim_del_augroup_by_id, state.group)
end

function M.detach_all()
  local bufs = vim.tbl_keys(states)
  for _, bufnr in ipairs(bufs) do
    M.detach(bufnr)
  end
end

-- -- Snacks-shaped entrypoints, so callers currently doing
-- -- `require("snacks.image").doc.attach(buf)` can switch to this module with the
-- -- smallest possible diff.
-- M.doc = {
--   attach = M.attach,
--   detach = M.detach,
-- }
--
-- M.inline = {
--   attach = M.attach,
--   detach = M.detach,
--   refresh = M.refresh,
-- }

vim.api.nvim_create_autocmd({ "VimLeavePre", "VimResized" }, {
  callback = function(ev)
    if ev.event == "VimResized" then
      terminal_size = nil
    else
      M.detach_all()
    end
  end,
})

return M
