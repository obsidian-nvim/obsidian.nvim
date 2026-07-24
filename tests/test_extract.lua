local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local h = dofile "tests/helpers.lua"

local T = new_set()
local extract = require "obsidian.extract"

local function temp_file(suffix, content)
  local path = vim.fn.tempname() .. suffix
  vim.fn.writefile(vim.split(content or "", "\n"), path, "b")
  return path
end

local function with_system(fn, body)
  local old_system = extract._set_system(fn)
  local ok, err = pcall(body)
  extract._set_system(old_system)
  if not ok then
    error(err)
  end
end

local function await_extract(path)
  local done = false
  local values
  extract.extract(path, function(err, result)
    values = { err, result }
    done = true
  end)
  vim.wait(1000, function()
    return done
  end)
  return unpack(values)
end

T["can_extract"] = new_set()

T["can_extract"]["supports existing images and PDFs"] = function()
  local image = temp_file ".png"
  local pdf = temp_file ".pdf"

  eq({ true }, { extract.can_extract(image) })
  eq({ true }, { extract.can_extract(pdf) })

  vim.fn.delete(image)
  vim.fn.delete(pdf)
end

T["can_extract"]["rejects missing and unsupported files"] = function()
  local missing = vim.fn.tempname() .. ".png"
  local text = temp_file ".txt"

  eq({ false, "file does not exist" }, { extract.can_extract(missing) })
  eq({ false, "unsupported file type" }, { extract.can_extract(text) })

  vim.fn.delete(text)
end

T["extract"] = new_set()

T["extract"]["extracts image text with tesseract"] = function()
  local image = temp_file ".png"

  with_system(function(cmd, cb)
    eq({ "tesseract", image, "stdout" }, cmd)
    cb { code = 0, stdout = "hello\n", stderr = "" }
    return {}
  end, function()
    local err, result = await_extract(image)
    eq(nil, err)
    eq("hello", result.text)
    eq("tesseract", result.engine)
  end)

  vim.fn.delete(image)
end

T["extract"]["extracts PDF text by pages with pdftotext"] = function()
  local pdf = temp_file ".pdf"

  with_system(function(cmd, cb)
    eq({ "pdftotext", "-layout", "-enc", "UTF-8", pdf, "-" }, cmd)
    cb { code = 0, stdout = "page one\fpage two\f", stderr = "" }
    return {}
  end, function()
    local err, result = await_extract(pdf)
    eq(nil, err)
    eq("page one\n\npage two", result.text)
    eq("pdftotext", result.engine)
    eq({ { page = 1, text = "page one" }, { page = 2, text = "page two" } }, result.pages)
  end)

  vim.fn.delete(pdf)
end

local T_code_action, child = h.child_vault {
  pre_case = [=[
M = require("obsidian.lsp.handlers._code_action").actions.extract_attachment_text
local attachment_dir = Obsidian.dir / "attachments"
attachment_dir:mkdir()
vim.fn.writefile({ "fake" }, tostring(attachment_dir / "image.png"), "b")
vim.api.nvim_buf_set_name(0, tostring(Obsidian.dir / "note.md"))
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "![[image.png]]" })
vim.api.nvim_win_set_cursor(0, { 1, 3 })
  ]=],
}

T["extract_attachment_text code action"] = T_code_action

T["extract_attachment_text code action"]["is available on extractable attachment links"] = function()
  eq(true, child.lua_get [[M.data.cond(require("obsidian.note").from_buffer(0))]])
end

T["extract_attachment_text code action"]["yanks extracted text"] = function()
  child.lua [[
vim.system = function(cmd, opts, cb)
  cb({ code = 0, stdout = "from image\n", stderr = "" })
  return {}
end
vim.lsp.commands["obsidian.extract_attachment_text"]({ arguments = {} })
  ]]
  h.child_wait(child, [[return vim.fn.getreg('"') == "from image"]], { desc = "extracted text register" })
end

return T
