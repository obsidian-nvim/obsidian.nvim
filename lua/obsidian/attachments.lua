local M = {}

---@enum obsidian.attachment.ft
local filetypes = {
  -- markdown
  "md",
  -- json canvas
  "canvas",
  -- images
  "avif",
  "bmp",
  "gif",
  "jpg",
  "jpeg",
  "png",
  "svg",
  "webp",
  -- audio
  "flac",
  "m4a",
  "mp3",
  "ogg",
  "wav",
  "webm",
  "3gp",
  -- video
  "mkv",
  "mov",
  "mp4",
  "ogv",
  "webm",
  -- pdf
  "pdf",
}

-- TODO: file extension to mime type and vice versa

M.filetypes = filetypes

return M
