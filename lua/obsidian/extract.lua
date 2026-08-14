local M = {}
local Path = require "obsidian.path"

---@alias obsidian.extract.Callback fun(err: string?, result: obsidian.extract.Result?)

---@class obsidian.extract.Page
---@field page integer
---@field text string

---@class obsidian.extract.Result
---@field path string
---@field text string
---@field engine string
---@field pages? obsidian.extract.Page[]
---@field diagnostics? string[]

local image_extensions = {
  avif = true,
  bmp = true,
  gif = true,
  jpg = true,
  jpeg = true,
  png = true,
  tif = true,
  tiff = true,
  webp = true,
}

local function trim_trailing(text)
  return (text or ""):gsub("%z", ""):gsub("%s+$", "")
end

local function finish(callback, err, result)
  vim.schedule(function()
    callback(err, result)
  end)
end

---@param path obsidian.Path
---@return boolean
---@return string?
M.can_extract = function(path)
  if not path or path == "" then
    return false, "path is empty"
  end

  if not path:exists() then
    return false, "file does not exist"
  end

  local ext = assert(path.suffix, "path no extension"):sub(2)
  if ext == "pdf" or image_extensions[ext] then
    return true
  end

  return false, "unsupported file type"
end

---@param cmd string[]
---@param callback fun(out: vim.SystemCompleted)
local function system(cmd, callback)
  local ok, handle = pcall(vim.system, cmd, { text = true }, callback)
  if not ok then
    callback { code = 1, signal = 0, stdout = "", stderr = tostring(handle) }
    return nil
  end
  return handle
end

---@param path string
---@param callback obsidian.extract.Callback
local function extract_image(path, callback)
  system({ "tesseract", path, "stdout" }, function(out)
    if out.code ~= 0 then
      return finish(callback, trim_trailing(out.stderr) ~= "" and trim_trailing(out.stderr) or "tesseract failed")
    end

    local text = trim_trailing(out.stdout)
    finish(callback, nil, {
      path = path,
      text = text,
      engine = "tesseract",
    })
  end)
end

---@param text string
---@return obsidian.extract.Page[]
local function pdf_pages(text)
  local pages = {}
  text = text or ""
  for page in (text .. "\f"):gmatch "(.-)\f" do
    page = trim_trailing(page)
    if page ~= "" then
      pages[#pages + 1] = { page = #pages + 1, text = page }
    end
  end
  return pages
end

---@param pages obsidian.extract.Page[]
---@return string
local function join_pages(pages)
  local parts = {}
  for _, page in ipairs(pages) do
    parts[#parts + 1] = page.text
  end
  return table.concat(parts, "\n\n")
end

---@param path string
---@param callback obsidian.extract.Callback
local function extract_pdf(path, callback)
  system({ "pdftotext", "-layout", "-enc", "UTF-8", path, "-" }, function(out)
    if out.code ~= 0 then
      return finish(callback, trim_trailing(out.stderr) ~= "" and trim_trailing(out.stderr) or "pdftotext failed")
    end

    local pages = pdf_pages(out.stdout or "")
    local text = join_pages(pages)
    finish(callback, nil, {
      path = path,
      text = text,
      engine = "pdftotext",
      pages = pages,
    })
  end)
end

---@param path string|obsidian.Path
---@param callback obsidian.extract.Callback
M.extract = function(path, callback)
  vim.validate("path", path, "string")
  vim.validate("callback", callback, "function")

  path = Path.new(path)

  local ok, reason = M.can_extract(path)
  if not ok then
    return finish(callback, reason)
  end

  local ext = assert(path.suffix, "path no extension"):sub(2)

  if ext == "pdf" then
    return extract_pdf(tostring(path), callback)
  elseif image_extensions[ext] then
    return extract_image(tostring(path), callback)
  end

  finish(callback, "unsupported file type")
end

return M
