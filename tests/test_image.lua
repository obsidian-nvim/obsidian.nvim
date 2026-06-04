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

    eq(pos.row + 1, calls[1].opts.row)
    eq(pos.col, calls[1].opts.col)
    assert(calls[1].opts.width <= 10)
    assert(calls[1].opts.height <= 5)

    local ns = vim.api.nvim_get_namespaces()["obsidian.image"]
    local extmarks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
    eq(1, #extmarks)
    eq(calls[1].opts.height, #extmarks[1][4].virt_lines)
  end)

  image.detach(0)
  vim.ui.img = original_img

  if not ok then
    error(err)
  end
end

return T
