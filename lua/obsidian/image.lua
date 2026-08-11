local attachment = require "obsidian.attachment"
local log = require "obsidian.log"
local util = require "obsidian.util"

local M = {}
local ns = vim.api.nvim_create_namespace "obsidian.image"

---@class obsidian.image.Opts
---@field placement? "inline"
---@field width? integer
---@field height? integer
---@field max_width? integer
---@field max_height? integer
---@field zindex? integer
---@field pad? integer
---@field conceal? boolean|string
---@field formats? string[]
---@field visible_only? boolean
---@field margin? integer
---@field debounce? integer
---@field enabled? boolean

---@class obsidian.image.Size
---@field width integer
---@field height integer

---@class obsidian.image.ResizeOpts
---@field step? integer Number of cells to add to or subtract from the largest dimension.

---@class obsidian.image.Match
---@field path string
---@field row integer 0-indexed
---@field col integer 0-indexed
---@field end_col integer 0-indexed, exclusive
---@field key string
---@field pad integer
---@field win integer
---@field width_px? number
---@field height_px? number

---@class obsidian.image.Rendered
---@field id? integer
---@field buf integer
---@field opts vim.ui.img.Opts
---@field size obsidian.image.Size
---@field anchor? integer
---@field spacer? integer

---@class obsidian.image.State
---@field buf integer
---@field group integer
---@field opts obsidian.image.Opts
---@field rendered table<string, obsidian.image.Rendered>
---@field resized table<string, obsidian.image.Size>
---@field timer uv.uv_timer_t?

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
}

---@param opts obsidian.image.Opts|?
---@return obsidian.image.Opts
local function normalize_opts(opts)
  return vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

---This only checks API availability. Calling `vim.ui.img._supported()` here would
---block the main loop while the terminal is queried, once for every attachment
---and (previously) every refresh.
---@return boolean
function M.supported()
  return type(vim.ui) == "table"
    and type(vim.ui.img) == "table"
    and type(vim.ui.img.set) == "function"
    and type(vim.ui.img.del) == "function"
end

---@param path string
---@return string
local function read_file(path)
  local fd = assert(io.open(path, "rb"))
  local data = assert(fd:read "*a")
  fd:close()
  return data
end

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

  ---@param offset integer
  ---@return integer
  local function be32(offset)
    return math.floor(
      header:byte(offset) * 0x1000000
        + header:byte(offset + 1) * 0x10000
        + header:byte(offset + 2) * 0x100
        + header:byte(offset + 3)
    )
  end

  image_dims[path] = { width = be32(17), height = be32(21) }
  return image_dims[path]
end

---@type { width: number, height: number }?
local cell_size

---Get the terminal cell size without issuing a blocking terminal query.
---@return { width: number, height: number }
local function terminal_cell_size()
  if cell_size then
    return cell_size
  end

  cell_size = { width = 10, height = 20 }
  local ok, ffi = pcall(require, "ffi")
  if not ok then
    return cell_size
  end

  pcall(
    ffi.cdef,
    [[
    typedef struct {
      unsigned short row, col, xpixel, ypixel;
    } obsidian_winsize;
    int ioctl(int, int, ...);
  ]]
  )

  local request
  if vim.fn.has "linux" == 1 then
    request = 0x5413
  elseif vim.fn.has "mac" == 1 or vim.fn.has "bsd" == 1 then
    request = 0x40087468
  end

  if request then
    pcall(function()
      local size = ffi.new "obsidian_winsize"
      if
        ffi.C.ioctl(1, request, size) == 0
        and size.col > 0
        and size.row > 0
        and size.xpixel > 0
        and size.ypixel > 0
      then
        cell_size = { width = size.xpixel / size.col, height = size.ypixel / size.row }
      end
    end)
  end

  return cell_size
end

---@param width number
---@param height number
---@return obsidian.image.Size
local function px_to_cells(width, height)
  local cell = terminal_cell_size()
  return {
    width = math.max(1, math.ceil(width / cell.width)),
    height = math.max(1, math.ceil(height / cell.height)),
  }
end

---@param size obsidian.image.Size
---@param bounds obsidian.image.Size
---@param upscale? boolean
---@return obsidian.image.Size
local function fit_size(size, bounds, upscale)
  local scale = math.min(bounds.width / size.width, bounds.height / size.height)
  if not upscale then
    scale = math.min(1, scale)
  end
  return {
    width = math.max(1, math.floor(size.width * scale + 0.5)),
    height = math.max(1, math.floor(size.height * scale + 0.5)),
  }
end

---@param spec string
---@return integer? width
---@return integer? height
local function parse_size(spec)
  local width_text, height_text = vim.trim(spec):match "^(%d+)x(%d+)$"
  if width_text and height_text then
    return math.floor(assert(tonumber(width_text))), math.floor(assert(tonumber(height_text)))
  end
  width_text = vim.trim(spec):match "^(%d+)$"
  return width_text and math.floor(assert(tonumber(width_text))) or nil, nil
end

---@param target string
---@return string
local function clean_target(target)
  target = vim.trim(target):gsub("^<(.+)>$", "%1")
  target = target:match "^(%S+)%s+['\"].-['\"]$" or target
  target = target:match "^([^|]+)" or target
  target = target:gsub("#.*$", ""):gsub("%?.*$", ""):gsub("\\ ", " ")
  return vim.uri_decode(target)
end

---@param path string
---@return boolean
local function exists(path)
  return path ~= "" and vim.uv.fs_stat(path) ~= nil
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
    return scheme == "file" and vim.uri_to_fname(src) or nil
  end

  if (vim.startswith(src, "/") or src:match "^%a:[/\\]") and exists(src) then
    return vim.fs.normalize(src)
  end

  local name = vim.api.nvim_buf_get_name(bufnr)
  local candidates = { vim.fs.joinpath(name ~= "" and vim.fs.dirname(name) or vim.fn.getcwd(), src) }
  if Obsidian and Obsidian.dir then
    candidates[#candidates + 1] = vim.fs.joinpath(tostring(Obsidian.dir), src)
  end
  if Obsidian and Obsidian.opts and Obsidian.opts.attachments then
    candidates[#candidates + 1] = attachment.resolve_attachment_path(src, bufnr)
  end

  for _, candidate in ipairs(candidates) do
    candidate = vim.fs.normalize(candidate)
    if exists(candidate) then
      return candidate
    end
  end
end

---@param line string
---@param row integer
---@param state obsidian.image.State
---@param win integer
---@return obsidian.image.Match[]
local function find_line_images(line, row, state, win)
  local matches = {}

  local function add(start_col, end_col, src, width_px, height_px)
    local path = resolve_path(src, state.buf)
    local ext = path and path:match "%.([^./\\]+)$"
    if not path or not ext or not vim.list_contains(state.opts.formats or defaults.formats, ext:lower()) then
      return
    end

    local key = table.concat({ row, start_col, end_col, path }, ":")
    matches[#matches + 1] = {
      path = path,
      row = row,
      col = start_col,
      end_col = end_col,
      key = key,
      pad = vim.fn.strdisplaywidth(line:sub(1, start_col)),
      win = win,
      width_px = width_px,
      height_px = height_px,
    }
  end

  for start_col, body, end_pos in line:gmatch "()!%[%[([^%]]+)%]%]()" do
    local size = body:match "|([^|]+)$"
    local width, height
    if size then
      width, height = parse_size(size)
    end
    add(start_col - 1, end_pos - 1, body, width, height)
  end

  for start_col, alt, target, end_pos in line:gmatch "()!%[([^%]]*)%]%(([^%)]+)%)()" do
    local width, height = parse_size(alt)
    add(start_col - 1, end_pos - 1, target, width, height)
  end

  return matches
end

---@param bufnr integer
---@return integer[]
local function visible_wins(bufnr)
  return vim.tbl_filter(function(win)
    return vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr
  end, vim.api.nvim_tabpage_list_wins(0))
end

---@param state obsidian.image.State
---@return obsidian.image.Match[]
local function find_images(state)
  local wins = visible_wins(state.buf)
  if #wins == 0 then
    return {}
  end

  local line_count = vim.api.nvim_buf_line_count(state.buf)
  ---@type { start_row: integer, end_row: integer, win: integer }[]
  local ranges = {}
  if state.opts.visible_only then
    for _, win in ipairs(wins) do
      local info = vim.fn.getwininfo(win)[1]
      if info then
        local margin = state.opts.margin or 0
        ranges[#ranges + 1] = {
          start_row = math.max(0, info.topline - 1 - margin),
          end_row = math.min(line_count, info.botline + margin),
          win = win,
        }
      end
    end
  else
    ranges[1] = { start_row = 0, end_row = line_count, win = assert(wins[1], "visible window missing") }
  end

  local matches, seen = {}, {}
  for _, range in ipairs(ranges) do
    local lines = vim.api.nvim_buf_get_lines(state.buf, range.start_row, range.end_row, false)
    for i, line in ipairs(lines) do
      for _, match in ipairs(find_line_images(line, range.start_row + i - 1, state, range.win)) do
        if not seen[match.key] then
          seen[match.key] = true
          matches[#matches + 1] = match
        end
      end
    end
  end
  return matches
end

---@param match obsidian.image.Match
---@param state obsidian.image.State
---@return obsidian.image.Size
local function bounds(match, state)
  local width = state.opts.width or state.opts.max_width or defaults.max_width
  local height = state.opts.height or state.opts.max_height or defaults.max_height
  local info = vim.api.nvim_win_is_valid(match.win) and vim.fn.getwininfo(match.win)[1] or nil
  if info then
    width = math.min(width, math.max(1, info.width - info.textoff - match.pad))
  end
  return { width = width, height = height }
end

---@param match obsidian.image.Match
---@param state obsidian.image.State
---@return obsidian.image.Size?
local function image_size(match, state)
  if state.resized[match.key] then
    return state.resized[match.key]
  end

  if match.width_px then
    local height = match.height_px
    if not height then
      local ok, dimensions = pcall(png_dims, match.path)
      if not ok then
        return nil
      end
      height = match.width_px * dimensions.height / dimensions.width
    end
    return px_to_cells(match.width_px, height)
  end

  local ok, dimensions = pcall(png_dims, match.path)
  if not ok then
    return nil
  end
  return fit_size(
    px_to_cells(dimensions.width, dimensions.height),
    bounds(match, state),
    state.opts.width ~= nil or state.opts.height ~= nil
  )
end

---@param path string
---@param width integer
---@return integer?
local function aspect_height(path, width)
  local ok, dimensions = pcall(png_dims, path)
  if not ok then
    return nil
  end
  local cell = terminal_cell_size()
  local height = (width * cell.width * dimensions.height) / (cell.height * dimensions.width)
  return math.max(1, math.floor(height + 0.5))
end

---@param match obsidian.image.Match
---@param state obsidian.image.State
---@return vim.ui.img.Opts?
---@return obsidian.image.Size?
local function image_opts(match, state)
  local measured = image_size(match, state)
  local width = measured and measured.width
  local height = width and aspect_height(match.path, width) or nil
  if not width or not height or not vim.api.nvim_win_is_valid(match.win) then
    return nil, nil
  end

  local size = { width = width, height = height }
  local start_pos = vim.fn.screenpos(match.win, match.row + 1, match.col + 1)
  local end_pos = vim.fn.screenpos(match.win, match.row + 1, match.end_col)
  if start_pos.row == 0 or start_pos.col == 0 or end_pos.row == 0 then
    return nil, size
  end

  return {
    relative = "ui",
    row = end_pos.row + 1,
    col = start_pos.col + (state.opts.pad or 0),
    -- The Kitty spec says one dimension is enough, but WezTerm currently leaves
    -- the omitted dimension at the source pixel size. Send an aspect-correct cell
    -- rectangle for consistent behavior across implementations.
    width = width,
    height = height,
    zindex = state.opts.zindex,
  },
    size
end

---@param rendered obsidian.image.Rendered
local function del_rendered(rendered)
  if rendered.id then
    pcall(vim.ui.img.del, rendered.id)
  end
  if vim.api.nvim_buf_is_valid(rendered.buf) then
    if rendered.anchor then
      pcall(vim.api.nvim_buf_del_extmark, rendered.buf, ns, rendered.anchor)
    end
    if rendered.spacer then
      pcall(vim.api.nvim_buf_del_extmark, rendered.buf, ns, rendered.spacer)
    end
  end
end

---@param rendered obsidian.image.Rendered
---@param state obsidian.image.State
---@param match obsidian.image.Match
local function update_spacer(rendered, state, match)
  local height = rendered.size.height

  local virt_lines = {}
  for i = 1, height do
    virt_lines[i] = { { " ", "Normal" } }
  end
  rendered.spacer = vim.api.nvim_buf_set_extmark(state.buf, ns, match.row, 0, {
    id = rendered.spacer,
    virt_lines = virt_lines,
    invalidate = true,
    undo_restore = false,
  })
end

---@param state obsidian.image.State
---@param match obsidian.image.Match
---@param rendered obsidian.image.Rendered?
---@param force boolean
---@return obsidian.image.Rendered?
local function render_match(state, match, rendered, force)
  if force then
    image_dims[vim.fs.normalize(match.path)] = nil
  end
  local opts, size = image_opts(match, state)
  if not opts then
    if rendered and rendered.id then
      pcall(vim.ui.img.del, rendered.id)
      rendered.id = nil
    end
    return rendered
  end
  ---@cast size -nil

  if rendered and rendered.id and not force then
    if vim.deep_equal(rendered.opts, opts) and vim.deep_equal(rendered.size, size) then
      return rendered
    end
    local ok, err = pcall(vim.ui.img.set, rendered.id, opts)
    if ok then
      rendered.opts = opts
      rendered.size = size
      update_spacer(rendered, state, match)
    else
      log.warn_once("Failed to update image: %s", err)
    end
    return rendered
  end

  if rendered and rendered.id then
    pcall(vim.ui.img.del, rendered.id)
    rendered.id = nil
  end

  local ok, data = pcall(read_file, match.path)
  if not ok then
    return rendered
  end
  local set_ok, id = pcall(vim.ui.img.set, data, opts)
  if not set_ok then
    log.warn_once("Failed to display image: %s", id)
    return rendered
  end

  rendered = rendered or { buf = state.buf, opts = opts, size = size }
  ---@cast rendered obsidian.image.Rendered
  rendered.id = id
  rendered.opts = opts
  rendered.size = size
  update_spacer(rendered, state, match)
  if state.opts.conceal and not rendered.anchor then
    rendered.anchor = vim.api.nvim_buf_set_extmark(state.buf, ns, match.row, match.col, {
      end_row = match.row,
      end_col = match.end_col,
      conceal = type(state.opts.conceal) == "string" and state.opts.conceal or "",
      invalidate = true,
      undo_restore = false,
    })
  end
  return rendered
end

---@param bufnr integer
---@param force? boolean
function M.refresh(bufnr, force)
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  local state = states[bufnr]
  if not state or not vim.api.nvim_buf_is_valid(bufnr) or not M.supported() then
    return
  end

  local next_rendered = {}
  for _, match in ipairs(find_images(state)) do
    local rendered = render_match(state, match, state.rendered[match.key], force == true)
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
---@param delay? integer
local function schedule_refresh(state, delay)
  if state.timer then
    state.timer:stop()
  else
    state.timer = assert(vim.uv.new_timer())
  end

  state.timer:start(
    delay or state.opts.debounce or 0,
    0,
    vim.schedule_wrap(function()
      M.refresh(state.buf)
    end)
  )
end

---@param size obsidian.image.Size
---@param delta integer
---@return obsidian.image.Size
local function resize(size, delta)
  local largest = math.max(size.width, size.height)
  local scale = math.max(1, largest + delta) / largest
  return {
    width = math.max(1, math.floor(size.width * scale + 0.5)),
    height = math.max(1, math.floor(size.height * scale + 0.5)),
  }
end

---Resize the image link under the cursor.
---@param delta integer
---@param opts? obsidian.image.ResizeOpts
---@param bufnr? integer
---@return boolean
function M.resize_under_cursor(delta, opts, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  local state = states[bufnr]
  local win = vim.api.nvim_get_current_win()
  if not state or delta == 0 or vim.api.nvim_win_get_buf(win) ~= bufnr then
    return false
  end

  local cursor = vim.api.nvim_win_get_cursor(win)
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1]
  if not line then
    return false
  end

  local match
  for _, candidate in ipairs(find_line_images(line, cursor[1] - 1, state, win)) do
    if candidate.col <= cursor[2] and cursor[2] < candidate.end_col then
      match = candidate
      break
    end
  end
  if not match then
    return false
  end

  local rendered = state.rendered[match.key]
  local current = image_size(match, state)
  if rendered then
    current = rendered.size
  end
  if not current then
    return false
  end

  local step = math.max(1, math.floor(tonumber(opts and opts.step) or math.abs(delta)))
  local next_size = resize(current, delta < 0 and -step or step)
  if vim.deep_equal(current, next_size) then
    return false
  end

  local previous = state.resized[match.key]
  state.resized[match.key] = next_size
  local next_rendered = render_match(state, match, rendered, false)
  if next_rendered then
    state.rendered[match.key] = next_rendered
    return true
  end
  state.resized[match.key] = previous
  return false
end

---@param opts? obsidian.image.ResizeOpts
---@return boolean
function M.increase_size(opts)
  return M.resize_under_cursor(1, opts)
end

---@param opts? obsidian.image.ResizeOpts
---@return boolean
function M.decrease_size(opts)
  return M.resize_under_cursor(-1, opts)
end

---@param bufnr? integer
---@param opts? obsidian.image.Opts
function M.attach(bufnr, opts)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
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

  vim.api.nvim_create_autocmd({ "BufWinEnter", "TextChanged", "TextChangedI" }, {
    group = state.group,
    buffer = bufnr,
    callback = function()
      schedule_refresh(state)
    end,
  })
  vim.api.nvim_create_autocmd("WinScrolled", {
    group = state.group,
    callback = function(ev)
      local win = tonumber(ev.match)
      ---@cast win integer?
      if win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
        schedule_refresh(state, 0)
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinResized", {
    group = state.group,
    callback = function()
      if #visible_wins(bufnr) > 0 then
        schedule_refresh(state, 0)
      end
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

---@param bufnr? integer
---@return boolean
function M.is_attached(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  return states[bufnr] ~= nil
end

---@param bufnr? integer
function M.detach(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  local state = states[bufnr]
  if not state then
    return
  end

  states[bufnr] = nil
  if state.timer then
    state.timer:stop()
    state.timer:close()
  end
  for _, rendered in pairs(state.rendered) do
    del_rendered(rendered)
  end
  pcall(vim.api.nvim_del_augroup_by_id, state.group)
end

function M.detach_all()
  for _, bufnr in ipairs(vim.tbl_keys(states)) do
    M.detach(bufnr)
  end
end

vim.api.nvim_create_autocmd("VimResized", {
  callback = function()
    cell_size = nil
    for _, state in pairs(states) do
      schedule_refresh(state, 0)
    end
  end,
})

vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = M.detach_all,
})

return M
