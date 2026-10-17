local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local T = new_set()
local preview = require "obsidian.preview"
local Range = require "obsidian.range"

T["location previews use live text and explicit range conversion"] = function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "éx", "end" })

  local lsp = preview.location {
    bufnr = bufnr,
    range = { start = { line = 0, character = 1 }, ["end"] = { line = 0, character = 2 } },
    encoding = "utf-16",
  }
  eq({ 1, 2 }, lsp.pos)
  eq({ 1, 3 }, lsp.pos_end)
  eq({ "éx", "end" }, vim.api.nvim_buf_get_lines(lsp.buf, 0, -1, false))

  local native = preview.location {
    bufnr = bufnr,
    range = Range.new(1, 0, 2, 0),
  }
  eq({ 2, 0 }, native.pos)
  eq({ 3, 0 }, native.pos_end)

  vim.api.nvim_buf_delete(lsp.buf, { force = true })
  vim.api.nvim_buf_delete(native.buf, { force = true })
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["unshown scratch previews are disposed on picker cleanup"] = function()
  local spec = preview.text({ "not displayed" }, "markdown")
  eq(true, vim.api.nvim_buf_is_valid(spec.buf))
  preview.cleanup_unshown()
  vim.wait(100, function()
    return not vim.api.nvim_buf_is_valid(spec.buf)
  end)
  eq(false, vim.api.nvim_buf_is_valid(spec.buf))
end

T["path previews prefer a loaded buffer over disk"] = function()
  local path = vim.fn.tempname()
  vim.fn.writefile({ "on disk" }, path)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, path)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "unsaved" })

  local spec = preview.path(path)
  eq("unsaved", vim.api.nvim_buf_get_lines(spec.buf, 0, 1, false)[1])

  vim.api.nvim_buf_delete(spec.buf, { force = true })
  vim.api.nvim_buf_delete(bufnr, { force = true })
  vim.fn.delete(path)
end

T["path previews handle missing and oversized files"] = function()
  local missing = preview.path(vim.fn.tempname())
  eq("Preview unavailable: file does not exist", vim.api.nvim_buf_get_lines(missing.buf, 0, 1, false)[1])

  local path = vim.fn.tempname()
  vim.fn.writefile({ "12345" }, path)
  local large = preview.path(path, { max_bytes = 4 })
  eq("Preview unavailable: file exceeds 4 bytes", vim.api.nvim_buf_get_lines(large.buf, 0, 1, false)[1])

  local binary_path = vim.fn.tempname()
  local fd = assert(vim.uv.fs_open(binary_path, "w", 438))
  assert(vim.uv.fs_write(fd, "a\0b", 0))
  vim.uv.fs_close(fd)
  local binary = preview.path(binary_path)
  eq("Preview unavailable: binary file", vim.api.nvim_buf_get_lines(binary.buf, 0, 1, false)[1])

  vim.api.nvim_buf_delete(missing.buf, { force = true })
  vim.api.nvim_buf_delete(large.buf, { force = true })
  vim.api.nvim_buf_delete(binary.buf, { force = true })
  vim.fn.delete(path)
  vim.fn.delete(binary_path)
end

return T
