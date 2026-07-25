local M = {}

M.note_extensions = {
  "md",
  "markdown",
  "qmd",
  "base",
}

M.attachment_extensions = {
  "canvas",
  "avif",
  "bmp",
  "gif",
  "jpg",
  "jpeg",
  "png",
  "svg",
  "webp",
  "flac",
  "m4a",
  "mp3",
  "ogg",
  "wav",
  "webm",
  "3gp",
  "mkv",
  "mov",
  "mp4",
  "ogv",
  "pdf",
}

local function extension_set(extensions)
  local set = {}
  for _, ext in ipairs(extensions) do
    set[ext] = true
  end
  return set
end

local note_extension_set = extension_set(M.note_extensions)
local attachment_extension_set = extension_set(M.attachment_extensions)

---@param path string
---@return string
function M.extension(path)
  return (path:match "%.([^./]+)$" or ""):lower()
end

---@param path string
---@return boolean
function M.is_note(path)
  return note_extension_set[M.extension(path)] == true
end

---@param path string
---@return boolean
function M.is_attachment(path)
  return attachment_extension_set[M.extension(path)] == true
end

---@param extensions string[]
---@return string
function M.glob(extensions)
  if #extensions == 1 then
    return "**/*." .. extensions[1]
  end
  return "**/*.{" .. table.concat(extensions, ",") .. "}"
end

return M
