local log = require "obsidian.log"
local source = require "obsidian.img.source"

local M = {}
local owners = {}
local next_owner_id = 0
local exit_autocmd
local buffer_support = setmetatable({}, { __mode = "k" })

local fallback_cell_width = 9
local fallback_cell_height = 18

---@param size { row: number, col: number, xpixel: number, ypixel: number }|nil
---@return number
function M.cell_aspect_ratio(size)
  if size and size.row > 0 and size.col > 0 and size.xpixel > 0 and size.ypixel > 0 then
    return (size.ypixel / size.row) / (size.xpixel / size.col)
  end
  return fallback_cell_height / fallback_cell_width
end

local function terminal_cell_aspect_ratio()
  local ok, ffi = pcall(require, "ffi")
  if not ok then
    return M.cell_aspect_ratio()
  end
  pcall(
    ffi.cdef,
    [[
    typedef struct {
      unsigned short row;
      unsigned short col;
      unsigned short xpixel;
      unsigned short ypixel;
    } obsidian_winsize;
    int ioctl(int, int, ...);
  ]]
  )

  local ioctl_request
  if vim.fn.has "linux" == 1 then
    ioctl_request = 0x5413
  elseif vim.fn.has "mac" == 1 or vim.fn.has "bsd" == 1 then
    ioctl_request = 0x40087468
  end
  if not ioctl_request then
    return M.cell_aspect_ratio()
  end

  local measured
  pcall(function()
    local size = ffi.new "obsidian_winsize"
    if ffi.C.ioctl(1, ioctl_request, size) == 0 then
      measured = { row = size.row, col = size.col, xpixel = size.xpixel, ypixel = size.ypixel }
    end
  end)
  return M.cell_aspect_ratio(measured)
end

---@class obsidian.img.Placement
---@field row? integer 1-indexed editor row
---@field col? integer 1-indexed editor column
---@field width? integer
---@field height? integer
---@field max_width? integer
---@field max_height? integer
---@field relative? string
---@field buf? integer Buffer used with relative='buffer'.
---@field pad? integer
---@field zindex? integer

---@alias obsidian.img.PlacementProvider obsidian.img.Placement|fun():obsidian.img.Placement

---@class obsidian.img.OwnerOpts
---@field kind? string
---@field win? integer
---@field buf? integer
---@field backend? table Test/provider override implementing set/get/del.
---@field max_bytes? integer

---@class obsidian.img.ShowOpts
---@field source obsidian.img.Source
---@field placement obsidian.img.PlacementProvider|nil
---@field require_buffer_lines? boolean Reject backends that do not reserve virtual lines for buffer images.

---@class obsidian.img.Owner
---@field id integer
---@field kind string
---@field win integer|nil
---@field buf integer|nil
---@field backend table|nil
---@field max_bytes integer|nil
---@field image_id integer|nil
---@field generation integer
---@field closed boolean
---@field autocmds integer[]
---@field placement obsidian.img.PlacementProvider|nil
---@field dimensions { width: integer, height: integer }|nil
local Owner = {}
Owner.__index = Owner

local function native_backend()
  return vim.ui and vim.ui.img or nil
end

---@param backend? table
---@return { api: boolean, png: boolean, terminal: string, editor: boolean }
function M.capabilities(backend)
  backend = backend or native_backend()
  local api = type(backend) == "table"
    and type(backend.set) == "function"
    and type(backend.get) == "function"
    and type(backend.del) == "function"
  return {
    api = api,
    png = api,
    -- There is no stable public terminal support probe. Actual placement is
    -- guarded and failures are returned to the caller.
    terminal = api and "unknown" or "unsupported",
    editor = api,
  }
end

---@param width integer
---@param height integer
---@param max_width integer
---@param max_height integer
---@return integer, integer
function M.fit(width, height, max_width, max_height)
  max_width = math.max(1, math.floor(max_width))
  max_height = math.max(1, math.floor(max_height))
  local ratio = (width / height) * terminal_cell_aspect_ratio()
  if max_width / max_height <= ratio then
    return max_width, math.max(1, math.floor(max_width / ratio + 0.5))
  else
    return math.max(1, math.floor(max_height * ratio + 0.5)), max_height
  end
end

---@param owner obsidian.img.Owner
local function delete_image(owner)
  local id = owner.image_id
  owner.image_id = nil
  if id and owner.backend and type(owner.backend.del) == "function" then
    local ok, err = pcall(owner.backend.del, id)
    if not ok then
      log.debug("Failed to delete image %s: %s", id, err)
    end
  end
end

---@param owner obsidian.img.Owner
---@return obsidian.img.Placement|nil
---@return string|nil
local function resolve_placement(owner)
  ---@type obsidian.img.PlacementProvider|nil
  local placement = owner.placement
  if type(placement) == "function" then
    local ok, value = pcall(placement)
    if not ok then
      return nil, "failed to calculate image placement: " .. tostring(value)
    end
    placement = value
  end
  if type(placement) ~= "table" then
    placement = {}
  else
    placement = vim.deepcopy(placement)
  end

  local dimensions = owner.dimensions
  if dimensions and placement.max_width and placement.max_height then
    placement.width, placement.height =
      M.fit(dimensions.width, dimensions.height, placement.max_width, placement.max_height)
  end
  placement.max_width = nil
  placement.max_height = nil
  return placement, nil
end

local function owner_is_valid(owner)
  if owner.closed then
    return false
  elseif owner.win and not vim.api.nvim_win_is_valid(owner.win) then
    return false
  elseif owner.buf and not vim.api.nvim_buf_is_valid(owner.buf) then
    return false
  end
  return true
end

-- Older vim.ui.img builds accept `relative = "buffer"` but silently render at
-- terminal coordinates. A new virtual-lines extmark is the observable public
-- contract that distinguishes a real inline placement from that UI fallback.
local function virtual_line_marks(bufnr)
  local marks = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, -1, 0, -1, { details = true })) do
    local details = mark[4]
    if details and details.virt_lines then
      marks[details.ns_id .. ":" .. mark[1]] = {
        row = mark[2],
        virt_lines = details.virt_lines,
        leftcol = details.virt_lines_leftcol,
      }
    end
  end
  return marks
end

local function call_callback(callback, ok, err)
  if callback then
    local success, callback_err = pcall(callback, ok, err)
    if not success then
      log.debug("Image callback failed: %s", callback_err)
    end
  end
end

---Display a PNG for this owner. A newer request cancels the previous request.
---@param opts obsidian.img.ShowOpts
---@param callback? fun(ok: boolean, err: string|nil)
---@return boolean started
---@return string|nil err
function Owner:show(opts, callback)
  if self.closed then
    return false, "image owner is closed"
  end
  opts = opts or {}
  self.generation = self.generation + 1
  local generation = self.generation
  delete_image(self)
  self.dimensions = nil
  self.placement = opts.placement

  local backend = self.backend
  if not M.capabilities(backend).api then
    local err = "vim.ui.img is unavailable"
    vim.schedule(function()
      if self.generation == generation and not self.closed then
        call_callback(callback, false, err)
      end
    end)
    return false, err
  end
  ---@cast backend table
  if opts.require_buffer_lines and buffer_support[backend] == false then
    local err = "vim.ui.img does not support buffer-relative images"
    vim.schedule(function()
      if self.generation == generation and not self.closed then
        call_callback(callback, false, err)
      end
    end)
    return false, err
  end

  source.load(opts.source, { max_bytes = self.max_bytes }, function(result, load_err)
    if self.generation ~= generation or not owner_is_valid(self) then
      return
    elseif not result then
      log.debug("Image load failed: %s", load_err)
      call_callback(callback, false, load_err)
      return
    end

    self.dimensions = { width = result.width, height = result.height }
    local placement, placement_err = resolve_placement(self)
    if not placement then
      call_callback(callback, false, placement_err)
      return
    end

    if opts.require_buffer_lines and buffer_support[backend] == false then
      call_callback(callback, false, "vim.ui.img does not support buffer-relative images")
      return
    end
    local before
    if opts.require_buffer_lines then
      if
        placement.relative ~= "buffer"
        or not placement.buf
        or not vim.api.nvim_buf_is_valid(placement.buf)
        or not placement.row
        or not placement.height
      then
        call_callback(callback, false, "buffer-relative placement requires a valid buffer")
        return
      end
      if buffer_support[backend] ~= true then
        before = virtual_line_marks(placement.buf)
      end
    end
    local ok, id = pcall(backend.set, result.bytes, placement)
    if not ok or type(id) ~= "number" or id % 1 ~= 0 then
      local err = ok and "vim.ui.img.set did not return an image id" or tostring(id)
      log.debug("Image placement failed: %s", err)
      call_callback(callback, false, err)
      return
    end
    self.image_id = math.floor(id)
    if before then
      local found = false
      local anchor_row = assert(placement.row, "buffer image row required")
      for key, mark in pairs(virtual_line_marks(placement.buf)) do
        if
          not before[key]
          and mark.row == anchor_row - 1
          and #mark.virt_lines == placement.height
          and not mark.leftcol
        then
          found = true
          break
        end
      end
      if not found then
        buffer_support[backend] = false
        delete_image(self)
        call_callback(callback, false, "vim.ui.img does not support buffer-relative images")
        return
      end
      buffer_support[backend] = true
    end
    call_callback(callback, true, nil)
  end)
  return true, nil
end

---Update the current image placement without retransmitting its bytes.
---@param placement? obsidian.img.PlacementProvider
---@return boolean
---@return string|nil
function Owner:update(placement)
  if placement ~= nil then
    self.placement = placement
  end
  if not owner_is_valid(self) or not self.image_id then
    return false, "image is not visible"
  end
  local resolved, err = resolve_placement(self)
  if not resolved then
    return false, err
  end
  local backend = self.backend
  if not backend or type(backend.set) ~= "function" then
    delete_image(self)
    return false, "vim.ui.img is unavailable"
  end
  local ok, result = pcall(backend.set, self.image_id, resolved)
  if not ok or type(result) ~= "number" then
    local update_err = ok and "vim.ui.img.set did not return an image id" or tostring(result)
    log.debug("Image update failed: %s", update_err)
    delete_image(self)
    return false, update_err
  end
  return true, nil
end

---Cancel pending work and remove only the image owned by this handle.
function Owner:close()
  if self.closed then
    return
  end
  self.closed = true
  self.generation = self.generation + 1
  delete_image(self)
  owners[self.id] = nil
  for _, autocmd in ipairs(self.autocmds) do
    pcall(vim.api.nvim_del_autocmd, autocmd)
  end
  self.autocmds = {}
end

local function ensure_exit_autocmd()
  if exit_autocmd then
    return
  end
  exit_autocmd = vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      M.clear_all()
    end,
  })
end

---Create a lifecycle owner for one UI surface.
---@param opts? obsidian.img.OwnerOpts
---@return obsidian.img.Owner
function M.owner(opts)
  opts = opts or {}
  next_owner_id = next_owner_id + 1
  local owner = setmetatable({
    id = next_owner_id,
    kind = opts.kind or "anonymous",
    win = opts.win,
    buf = opts.buf,
    backend = opts.backend or native_backend(),
    max_bytes = opts.max_bytes,
    generation = 0,
    closed = false,
    autocmds = {},
  }, Owner)
  owners[owner.id] = owner
  ensure_exit_autocmd()

  if owner.win and vim.api.nvim_win_is_valid(owner.win) then
    owner.autocmds[#owner.autocmds + 1] = vim.api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(owner.win),
      once = true,
      callback = function()
        owner:close()
      end,
    })
  end
  if owner.buf and vim.api.nvim_buf_is_valid(owner.buf) then
    owner.autocmds[#owner.autocmds + 1] = vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = owner.buf,
      once = true,
      callback = function()
        owner:close()
      end,
    })
  end
  return owner
end

---Convenience helper that creates an owner and starts one image request.
---@param source_spec obsidian.img.Source
---@param placement? obsidian.img.PlacementProvider
---@param opts? obsidian.img.OwnerOpts
---@param callback? fun(ok: boolean, err: string|nil)
---@return obsidian.img.Owner
function M.show(source_spec, placement, opts, callback)
  local owner = M.owner(opts)
  owner:show({ source = source_spec, placement = placement }, callback)
  return owner
end

---@param owner obsidian.img.Owner
function M.clear(owner)
  if owner and owner.close then
    owner:close()
  end
end

function M.clear_all()
  local active = vim.tbl_values(owners)
  for _, owner in ipairs(active) do
    owner:close()
  end
end

return M
