local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local h = dofile "tests/helpers.lua"

local T = h.temp_vault

T["inline"] = new_set()

local function write_png_header(path, width, height)
  local function be32(n)
    return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
  end

  local fd = assert(io.open(path, "wb"))
  fd:write("\137PNG\r\n\26\n" .. be32(13) .. "IHDR" .. be32(width) .. be32(height))
  fd:close()
end

T["inline"]["renders a fitted image below the image link"] = function()
  local image = require "obsidian.image"
  local original_img = vim.ui.img
  local calls = {}

  vim.ui.img = {
    set = function(data_or_id, opts)
      calls[#calls + 1] = { data_or_id = data_or_id, opts = opts }
      return #calls
    end,
    get = function(id)
      return calls[id] and calls[id].opts
    end,
    del = function()
      return true
    end,
  }

  local ok, err = pcall(function()
    local img_path = vim.fs.joinpath(tostring(Obsidian.dir), "img.png")
    local note_path = vim.fs.joinpath(tostring(Obsidian.dir), "note.md")
    write_png_header(img_path, 900, 360)
    vim.api.nvim_buf_set_name(0, note_path)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "  ![[img.png]]", "text below" })

    local win = vim.api.nvim_get_current_win()
    local pos = vim.fn.screenpos(win, 1, 3)

    image.attach(0, { debounce = 0, visible_only = true, max_width = 10, max_height = 5 })
    h.wait(function()
      return #calls > 0
    end)

    eq("buffer", calls[1].opts.relative)
    eq(1, calls[1].opts.row)
    eq(1, calls[1].opts.col)
    eq(pos.col - 1, calls[1].opts.pad)
    assert(calls[1].opts.width <= 10, "image width should fit max_width")
    assert(calls[1].opts.height <= 5, "image height should fit max_height")
  end)

  image.detach(0)
  vim.ui.img = original_img

  if not ok then
    error(err)
  end
end

T["inline"]["uses Obsidian embed dimensions"] = function()
  local image = require "obsidian.image"
  local original_img = vim.ui.img
  local calls = {}

  vim.ui.img = {
    set = function(data_or_id, opts)
      calls[#calls + 1] = { data_or_id = data_or_id, opts = opts }
      return #calls
    end,
    get = function(id)
      return calls[id] and calls[id].opts
    end,
    del = function()
      return true
    end,
  }

  local ok, err = pcall(function()
    local img_path = vim.fs.joinpath(tostring(Obsidian.dir), "sized.png")
    local note_path = vim.fs.joinpath(tostring(Obsidian.dir), "sized-note.md")
    write_png_header(img_path, 900, 360)
    vim.api.nvim_buf_set_name(0, note_path)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "![[sized.png|90x36]]" })

    image.attach(0, { debounce = 0, visible_only = true, max_width = 1, max_height = 1 })
    h.wait(function()
      return #calls > 0
    end)

    assert(calls[1].opts.width > 1, "embed width should override max_width")
    eq("buffer", calls[1].opts.relative)
  end)

  image.detach(0)
  vim.ui.img = original_img

  if not ok then
    error(err)
  end
end

T["inline"]["resizes the image under the cursor"] = function()
  local image = require "obsidian.image"
  local api = require "obsidian.api"
  local original_img = vim.ui.img
  local calls = {}

  vim.ui.img = {
    set = function(data_or_id, opts)
      if type(data_or_id) == "number" then
        calls[data_or_id].opts = opts
        return data_or_id
      end
      calls[#calls + 1] = { data_or_id = data_or_id, opts = opts }
      return #calls
    end,
    get = function(id)
      return calls[id] and calls[id].opts
    end,
    del = function()
      return true
    end,
  }

  local ok, err = pcall(function()
    local img_path = vim.fs.joinpath(tostring(Obsidian.dir), "resize.png")
    local note_path = vim.fs.joinpath(tostring(Obsidian.dir), "resize-note.md")
    write_png_header(img_path, 90, 45)
    vim.api.nvim_buf_set_name(0, note_path)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "![[resize.png]]" })
    vim.api.nvim_win_set_cursor(0, { 1, 3 })

    image.attach(0, { debounce = 0, visible_only = true, width = 10, height = 5 })
    h.wait(function()
      return #calls > 0
    end)

    eq(10, calls[1].opts.width)
    eq(5, calls[1].opts.height)

    eq(true, api.image_bigger())
    eq(11, calls[1].opts.width)
    eq(6, calls[1].opts.height)

    eq(true, api.image_smaller())
    eq(10, calls[1].opts.width)
    eq(5, calls[1].opts.height)
  end)

  image.detach(0)
  vim.ui.img = original_img

  if not ok then
    error(err)
  end
end

return T
