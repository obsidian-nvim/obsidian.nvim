local eq = MiniTest.expect.equality
local Path = require "obsidian.path"
local embed = require "obsidian.img.embed"
local attachment = require "obsidian.attachment"
local source = require "obsidian.img.source"

local original_img = vim.ui.img
local original_resolve = attachment._resolve_async
local original_load = source.load
local cleanup
local T = MiniTest.new_set {
  hooks = {
    post_case = function()
      embed.setup({ root = "", name = "test" }, { enabled = false })
      if cleanup then
        cleanup()
        cleanup = nil
      end
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
    set = function(data_or_id, opts)
      local id = type(data_or_id) == "number" and data_or_id or #placed + 1
      local virtual = {}
      for _ = 1, opts.height do
        virtual[#virtual + 1] = { { string.rep(" ", opts.width), "Normal" } }
      end
      marks[id] = vim.api.nvim_buf_set_extmark(buf, ns, opts.row - 1, opts.col - 1, {
        id = marks[id],
        virt_lines = virtual,
      })
      placed[#placed + 1] = opts
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
  eq({}, deleted) -- move the existing placement, do not retransmit it

  local popup_buf = vim.api.nvim_create_buf(false, true)
  local popup = vim.api.nvim_open_win(popup_buf, true, {
    relative = "editor",
    row = 1,
    col = 1,
    width = 20,
    height = 4,
  })
  vim.api.nvim_exec_autocmds("TextChangedP", { buffer = buf })
  vim.api.nvim_exec_autocmds("WinResized", {})
  vim.wait(200)
  eq(2, #placed) -- completion floats and unchanged geometry are no-ops
  eq({}, deleted)
  vim.api.nvim_win_close(popup, true)
  vim.api.nvim_buf_delete(popup_buf, { force = true })
  vim.api.nvim_exec_autocmds("WinEnter", {})
  vim.wait(200)
  eq(2, #placed)
  eq({}, deleted)

  vim.api.nvim_win_set_buf(win, original_buf)
  vim.api.nvim_buf_delete(buf, { force = true })
  eq({ 1 }, deleted)
  vim.wo[win].number = original_number
  vim.fn.delete(tostring(dir), "rf")
end

local function fixture(lines)
  local dir = Path.temp { suffix = "-img-lifecycle" }
  dir:mkdir { parents = true }
  local win = vim.api.nvim_get_current_win()
  local original_buf = vim.api.nvim_win_get_buf(win)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, tostring(dir / "Note.md"))
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local calls = { created = 0, updated = {}, deleted = {}, active = {} }
  vim.ui.img = {
    set = function(data, opts)
      local id = data
      if type(data) == "string" then
        calls.created = calls.created + 1
        id = calls.created
      else
        calls.updated[#calls.updated + 1] = id
      end
      calls.active[id] = opts
      return id
    end,
    get = function(id)
      return calls.active[id]
    end,
    del = function(id)
      calls.deleted[#calls.deleted + 1] = id
      calls.active[id] = nil
    end,
  }
  attachment._resolve_async = function(target, _, callback)
    callback(tostring(dir / target))
  end
  source.load = function(_, callback)
    callback { bytes = "png", width = 600, height = 300 }
  end
  embed.setup({ root = dir, name = "test" }, { enabled = true })
  vim.api.nvim_win_set_buf(win, buf)
  cleanup = function()
    vim.api.nvim_win_set_buf(win, original_buf)
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.fn.delete(tostring(dir), "rf")
  end
  return buf, calls
end

local function changed(buf)
  vim.api.nvim_exec_autocmds("TextChangedP", { buffer = buf })
  vim.wait(200)
end

T["reconciles individual embeds without disturbing other occurrences"] = function()
  local buf, calls = fixture { "![[one.png]]", "text", "![[two.png]]", "![[one.png]]" }
  embed.refresh(buf)
  eq(3, calls.created)
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "typing a completion query" })
  changed(buf)
  eq(3, calls.created)
  eq({}, calls.updated)
  eq({}, calls.deleted)

  vim.api.nvim_buf_set_lines(buf, 2, 3, false, { "![[three.png]]" })
  changed(buf)
  eq(4, calls.created)
  eq({ 2 }, calls.deleted)
  eq({}, calls.updated)
  eq(1, calls.active[1].row)
  eq(4, calls.active[3].row)

  vim.api.nvim_buf_set_lines(buf, 0, 1, false, {})
  changed(buf)
  eq(4, calls.created)
  eq({ 2, 3 }, calls.deleted) -- one duplicate remains owned
  eq(3, calls.active[1].row)
  eq(2, calls.active[4].row)
end

T["layout changes update IDs and hidden buffers retain inline owners"] = function()
  local buf, calls = fixture { "![[one.png]]" }
  embed.refresh(buf)
  local win = vim.api.nvim_get_current_win()
  vim.cmd "vsplit"
  local split = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(split, 20)
  vim.api.nvim_exec_autocmds("WinResized", {})
  vim.wait(200)
  eq(1, calls.created)
  eq({}, calls.deleted)
  eq(true, #calls.updated > 0)
  eq(true, calls.active[1].width <= 20)
  vim.api.nvim_win_close(split, true)
  vim.wait(200)
  eq(1, calls.created)
  eq({}, calls.deleted)

  local other = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(win, other)
  vim.api.nvim_exec_autocmds("WinResized", {})
  vim.wait(200)
  eq({}, calls.deleted)
  vim.api.nvim_win_set_buf(win, buf)
  vim.wait(200)
  eq(1, calls.created)
  eq({}, calls.deleted)
  vim.api.nvim_buf_delete(other, { force = true })
  vim.cmd "bunload!"
  eq({ 1 }, calls.deleted)
end

T["pending loads survive unrelated edits and use the latest anchor"] = function()
  local buf, calls = fixture { "![[one.png]]", "![[two.png]]" }
  local pending = {}
  source.load = function(_, callback)
    pending[#pending + 1] = callback
  end
  embed.refresh(buf)
  eq(2, #pending)
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "new heading" })
  changed(buf)
  eq(2, #pending)
  pending[1] { bytes = "png", width = 600, height = 300 }
  eq(2, calls.active[1].row)
  vim.api.nvim_buf_set_lines(buf, 2, 3, false, { "removed" })
  changed(buf)
  pending[2] { bytes = "png", width = 600, height = 300 }
  eq(1, calls.created) -- removed embed cannot resurrect
  eq({}, calls.deleted)
end

T["size labels and embed syntax only update placement"] = function()
  local buf, calls = fixture { "![[one.png|300]]" }
  embed.refresh(buf)
  local width = calls.active[1].width
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "![[one.png|100]]" })
  changed(buf)
  eq(1, calls.created)
  eq({ 1 }, calls.updated)
  eq({}, calls.deleted)
  eq(true, calls.active[1].width < width)
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "![alt](one.png)" })
  changed(buf)
  eq(1, calls.created)
  eq({}, calls.deleted)
end

T["opening and dismissing a real completion menu retains the image"] = function()
  local child = MiniTest.new_child_neovim()
  child.restart { "-u", "scripts/minimal_init.lua" }
  MiniTest.finally(function()
    child.stop()
  end)
  child.lua [=[
local embed = require "obsidian.img.embed"
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
_G.image_test_dir = dir
_G.image_calls = { created = 0, deleted = {} }
vim.ui.img = {
  set = function(data)
    if type(data) == "string" then image_calls.created = image_calls.created + 1 end
    return 1
  end,
  get = function() end,
  del = function(id) table.insert(image_calls.deleted, id) end,
}
require("obsidian.attachment")._resolve_async = function(_, _, callback)
  callback(dir .. "/image.png")
end
require("obsidian.img.source").load = function(_, callback)
  callback { bytes = "png", width = 600, height = 300 }
end
vim.api.nvim_buf_set_name(0, dir .. "/Note.md")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "![[image.png]]", "query" })
embed.setup({ root = dir, name = "test" }, { enabled = true })
vim.api.nvim_exec_autocmds("BufEnter", { buffer = 0 })
embed.refresh()
vim.o.completeopt = "menuone,noselect,noinsert"
vim.api.nvim_win_set_cursor(0, { 2, 0 })
  ]=]
  child.type_keys "A"
  child.lua [[vim.fn.complete(1, { "query-one", "query-two" })]]
  eq(1, child.lua_get "vim.fn.pumvisible()")
  local during = child.lua [[
vim.api.nvim_exec_autocmds("WinResized", {})
vim.wait(200)
return image_calls
  ]]
  eq(1, during.created)
  eq({}, during.deleted)
  child.type_keys("<C-e>", "<Esc>")
  local after = child.lua [[vim.wait(200); return image_calls]]
  eq(1, after.created)
  eq({}, after.deleted)
  child.lua [[
require("obsidian.img.embed").setup({ root = image_test_dir, name = "test" }, { enabled = false })
vim.fn.delete(image_test_dir, "rf")
  ]]
  eq({ 1 }, child.lua_get "image_calls.deleted")
  child.stop()
end

return T
