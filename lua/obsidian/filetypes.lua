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
  "3gp",
  "mkv",
  "mov",
  "mp4",
  "ogv",
  "webm",
  "pdf",
}

---@param extensions string[]
---@return table<string, boolean>
local function extension_set(extensions)
  local set = {}
  for _, ext in ipairs(extensions) do
    set[ext] = true
  end
  return set
end

local note_extensions = extension_set(M.note_extensions)
local attachment_extensions = extension_set(M.attachment_extensions)

---@param path string
---@return string
function M.extension(path)
  return (path:match "%.([^./\\]+)$" or ""):lower()
end

---@param path string
---@return boolean
function M.is_note(path)
  return note_extensions[M.extension(path)] == true
end

---@param path string
---@return boolean
function M.is_attachment(path)
  return attachment_extensions[M.extension(path)] == true
end

---@param path string
---@return "note"|"attachment"|nil
function M.kind(path)
  if M.is_note(path) then
    return "note"
  elseif M.is_attachment(path) then
    return "attachment"
  end
end

return M
