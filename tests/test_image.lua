local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local h = dofile "tests/helpers.lua"

local T = h.temp_vault

T["inline"] = new_set()

T["inline"]["renders buffer-relative image below the image link"] = function()
  local image = require "obsidian.image"
  local original_img = vim.ui.img
  local calls = {}

  vim.ui.img = {
    set = function(_, opts)
      calls[#calls + 1] = opts
      return #calls
    end,
    del = function()
      return true
    end,
  }

  local ok, err = pcall(function()
    local img_path = vim.fs.joinpath(tostring(Obsidian.dir), "img.png")
    local note_path = vim.fs.joinpath(tostring(Obsidian.dir), "note.md")
    vim.fn.writefile({ "png" }, img_path)
    vim.api.nvim_buf_set_name(0, note_path)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "  ![[img.png]]", "text below" })

    image.attach(0, { debounce = 0, visible_only = true, height = 3 })
    h.wait(function()
      return #calls > 0
    end)

    eq("buffer", calls[1].relative)
    eq(vim.api.nvim_get_current_buf(), calls[1].buf)
    eq(1, calls[1].row)
    eq(3, calls[1].col)
    eq(2, calls[1].pad)
    eq(3, calls[1].height)

    local ns = vim.api.nvim_get_namespaces()["obsidian.image"]
    eq({}, vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {}))
  end)

  image.detach(0)
  vim.ui.img = original_img

  if not ok then
    error(err)
  end
end

return T
