local eq = MiniTest.expect.equality
local Path = require "obsidian.path"
local embed = require "obsidian.img.embed"
local attachment = require "obsidian.attachment"
local source = require "obsidian.img.source"

local original_img = vim.ui.img
local original_resolve = attachment._resolve_async
local original_load = source.load
local T = MiniTest.new_set {
  hooks = {
    post_case = function()
      embed.setup({ root = "", name = "test" }, { enabled = false })
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
  local placed, deleted, marks = {}, {}, {}
  vim.ui.img = {
    set = function(_, opts)
      local id = #placed + 1
      local virtual = {}
      for _ = 1, opts.height do
        virtual[#virtual + 1] = { { string.rep(" ", opts.width), "Normal" } }
      end
      marks[id] = vim.api.nvim_buf_set_extmark(buf, ns, opts.row - 1, opts.col - 1, {
        virt_lines = virtual,
      })
      placed[id] = opts
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
  source.load = function(_, callback)
    callback({ bytes = "png", width = 600, height = 300 }, nil)
  end

  embed.setup({ root = dir, name = "test" }, { enabled = true })
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
  eq(
    true,
    vim.wait(1000, function()
      return #placed == 2
    end)
  )
  eq(3, placed[2].row)
  eq({ 1 }, deleted)

  vim.api.nvim_exec_autocmds("WinEnter", {})
  vim.wait(200)
  eq(2, #placed) -- a window switch must not delete/retransmit the image
  eq({ 1 }, deleted)

  vim.api.nvim_win_set_buf(win, original_buf)
  vim.api.nvim_buf_delete(buf, { force = true })
  eq(2, #deleted)
  vim.wo[win].number = original_number
  vim.fn.delete(tostring(dir), "rf")
end

return T
