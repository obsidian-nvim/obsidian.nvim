local eq = MiniTest.expect.equality
local Path = require "obsidian.path"
local img = require "obsidian.img"
local embed = require "obsidian.img.embed"
local actions = require "obsidian.actions"
local attachment = require "obsidian.attachment"
local source = require "obsidian.img.source"

local original_img = vim.ui.img
local original_resolve = attachment._resolve_async
local original_load = source.load
local T = MiniTest.new_set {
  hooks = {
    post_case = function()
      embed.setup({ root = "", name = "test" }, { enabled = false })
      img.clear_all()
      vim.ui.img = original_img
      attachment._resolve_async = original_resolve
      source.load = original_load
    end,
  },
}

local function be32(n)
  return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
end

T["embeds reserve rows below the link in the buffer text area"] = function()
  local dir = Path.temp { suffix = "-img-embed" }
  dir:mkdir { parents = true }
  local path = tostring(dir / "image.png")
  local file = assert(io.open(path, "wb"))
  file:write("\137PNG\r\n\26\n" .. be32(13) .. "IHDR" .. be32(600) .. be32(300) .. "\8\6\0\0\0\0\0\0\0")
  file:close()

  local win = vim.api.nvim_get_current_win()
  local original_buf = vim.api.nvim_win_get_buf(win)
  local original_number = vim.wo[win].number
  vim.wo[win].number = true
  local buf = vim.api.nvim_create_buf(true, false)
  local filename = tostring(dir / "Note.md")
  vim.api.nvim_buf_set_name(buf, filename)
  local lines = { "heading", "![[image.png|300]]", "after", "`![[image.png]]`" }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modified = false

  local ns = vim.api.nvim_create_namespace "ObsidianImgEmbedTest"
  local placed, deleted, updated, marks = {}, {}, {}, {}
  vim.ui.img = {
    set = function(bytes_or_id, opts)
      local id = type(bytes_or_id) == "number" and bytes_or_id or #placed + 1
      local virtual = {}
      for _ = 1, opts.height do
        virtual[#virtual + 1] = { { string.rep(" ", opts.width), "Normal" } }
      end
      marks[id] = vim.api.nvim_buf_set_extmark(buf, ns, opts.row - 1, opts.col - 1, {
        id = marks[id],
        virt_lines = virtual,
      })
      if type(bytes_or_id) == "number" then
        updated[#updated + 1] = opts
      else
        placed[id] = opts
      end
      return id
    end,
    get = function() end,
    del = function(id)
      deleted[#deleted + 1] = id
      vim.api.nvim_buf_del_extmark(buf, ns, marks[id])
    end,
  }
  local resolved
  attachment._resolve_async = function(ref, context, callback)
    resolved = { ref = ref, context = context }
    callback(path)
    return function() end
  end
  source.load = function(_, _, callback)
    callback({ bytes = "png", width = 600, height = 300 }, nil)
  end

  embed.setup({ root = dir, name = "test" }, {
    enabled = true,
    max_file_size = 1024 * 1024,
    embeds = { enabled = true },
  })
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_exec_autocmds("BufEnter", { buffer = buf })
  embed.refresh(buf)
  eq(1, #placed)
  eq("image.png", resolved.ref)
  eq(filename, resolved.context.filename)
  eq(buf, resolved.context.bufnr)
  eq(2, placed[1].row) -- upstream anchors below row 2 (1-indexed)
  eq(1, placed[1].col) -- buffer column, not screen or link column
  eq(0, placed[1].pad)
  eq("buffer", placed[1].relative)
  local info = vim.fn.getwininfo(win)[1]
  eq(true, info.textoff > 0)
  eq(true, placed[1].width <= info.width - info.textoff)
  local mark = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })[1]
  eq(1, mark[2]) -- virtual rows are below the embed, not over it
  eq(0, mark[3])
  eq(placed[1].height, #mark[4].virt_lines)
  eq(false, mark[4].virt_lines_leftcol)
  eq(lines, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  eq(false, vim.bo[buf].modified)

  vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "new first line" })
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
  vim.wait(150)
  eq(1, #placed)
  eq({}, deleted)
  local moved_mark = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })[1]
  eq(2, moved_mark[2])

  embed.refresh(buf)
  eq(2, #placed)
  eq(3, placed[2].row)
  eq({ 1 }, deleted)

  vim.api.nvim_win_set_cursor(win, { 3, 5 })
  local initial_height = placed[#placed].height
  eq(true, actions.increment())
  local grown_width = tonumber(vim.api.nvim_buf_get_lines(buf, 2, 3, false)[1]:match "^!%[%[image%.png|(%d+)%]%]$")
  eq(true, grown_width > 300)
  eq(initial_height + 1, placed[#placed].height)
  eq(true, actions.decrement())
  local shrunk_width = tonumber(vim.api.nvim_buf_get_lines(buf, 2, 3, false)[1]:match "^!%[%[image%.png|(%d+)%]%]$")
  eq(true, shrunk_width < grown_width)
  eq(initial_height, placed[#placed].height)
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  eq(false, actions.increment())
  eq("new first line", vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])

  vim.api.nvim_buf_set_lines(buf, 2, 3, false, { "![[image.png|300x200]]" })
  embed.refresh(buf)
  vim.api.nvim_win_set_cursor(win, { 3, 5 })
  local cell_width, cell_height = img.cell_pixels()
  eq(true, placed[#placed].width <= math.ceil(300 / cell_width))
  eq(true, placed[#placed].height <= math.ceil(200 / cell_height))
  local initial_height_with_bound = placed[#placed].height
  eq(true, actions.increment())
  local grown_width_with_bound, grown_height_with_bound =
    vim.api.nvim_buf_get_lines(buf, 2, 3, false)[1]:match "^!%[%[image%.png|(%d+)x(%d+)%]%]$"
  eq(true, tonumber(grown_width_with_bound) > 300)
  eq(true, math.abs(tonumber(grown_height_with_bound) / tonumber(grown_width_with_bound) - 200 / 300) < 0.01)
  eq(initial_height_with_bound + 1, placed[#placed].height)

  local text_width = vim.fn.getwininfo(win)[1].width - vim.fn.getwininfo(win)[1].textoff
  local width_limit = math.floor(math.min(80, text_width) * cell_width)
  local height_limit = math.floor(math.min(width_limit, 30 * cell_height))
  vim.api.nvim_buf_set_lines(buf, 2, 3, false, { ("![[image.png|%dx1]]"):format(width_limit) })
  embed.refresh(buf)
  eq(false, actions.increment()) -- width cap
  vim.api.nvim_buf_set_lines(buf, 2, 3, false, { ("![[image.png|%dx%d]]"):format(height_limit, height_limit) })
  embed.refresh(buf)
  eq(false, actions.increment()) -- height cap
  local before_shrink = placed[#placed].height
  eq(true, actions.decrement())
  eq(before_shrink - 1, placed[#placed].height)
  local next_width, next_height =
    vim.api.nvim_buf_get_lines(buf, 2, 3, false)[1]:match "^!%[%[image%.png|(%d+)x(%d+)%]%]$"
  eq(next_width, next_height)

  -- A wide image needs a larger pixel-width change to move by one row.
  source.load = function(_, _, callback)
    callback({ bytes = "png", width = 1200, height = 100 }, nil)
  end
  vim.api.nvim_buf_set_lines(buf, 2, 3, false, { "![[image.png|600]]" })
  embed.refresh(buf)
  local wide_height = placed[#placed].height
  eq(true, wide_height >= 2)
  eq(true, actions.decrement())
  eq(wide_height - 1, placed[#placed].height)
  local wide_width = tonumber(vim.api.nvim_buf_get_lines(buf, 2, 3, false)[1]:match "^!%[%[image%.png|(%d+)%]%]$")
  eq(true, 600 - wide_width > cell_width)
  eq(true, actions.decrement())
  eq(wide_height - 2, placed[#placed].height)
  eq(false, actions.decrement()) -- height cannot shrink below one cell
  source.load = function(_, _, callback)
    callback({ bytes = "png", width = 600, height = 300 }, nil)
  end

  vim.api.nvim_buf_set_lines(buf, 2, 3, false, { "![[image.png|alias]]" })
  embed.refresh(buf)
  eq(false, actions.increment())
  eq("![[image.png|alias]]", vim.api.nvim_buf_get_lines(buf, 2, 3, false)[1])

  vim.api.nvim_buf_set_lines(buf, 2, 3, false, { "![[image.png]]" })
  embed.refresh(buf)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local creations = #placed
  eq(true, actions.decrement())
  eq(true, actions.decrement())
  eq("![[image.png]]", vim.api.nvim_buf_get_lines(buf, 2, 3, false)[1])
  eq(tick, vim.api.nvim_buf_get_changedtick(buf))
  eq(creations, #placed)
  eq(2, #updated)
  eq(placed[creations].height - 1, updated[1].height)
  eq(updated[1].height - 1, updated[2].height)
  eq(true, updated[2].width < updated[1].width)
  vim.api.nvim_win_set_cursor(win, { 5, 5 }) -- link syntax inside inline code
  eq(false, actions.increment())

  local before = #placed
  vim.api.nvim_exec_autocmds("WinEnter", {}) -- returning from the message pager
  vim.wait(150)
  eq(before + 1, #placed)
  eq(before, #deleted)
  eq(updated[2].width, placed[#placed].width)

  vim.api.nvim_win_set_buf(win, original_buf)
  vim.api.nvim_buf_delete(buf, { force = true })
  eq(#placed, #deleted)
  vim.wo[win].number = original_number
  vim.fn.delete(tostring(dir), "rf")
end

return T
