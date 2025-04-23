-- accpeted file formats: https://help.obsidian.md/file-formats

---@enum obsidian.attachment.ft
local ft = {
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

local function insert_link(client, dst)
  local new_link = "!" .. client:format_link(dst)
  vim.api.nvim_put({ new_link }, "l", true, true)
end

---@param str string
---@return string
local sanitize_input = function(str)
  str = str:match "^%s*(.-)%s*$" -- remove leading and trailing whitespace
  str = str:match '^"?(.-)"?$' -- remove double quotes
  str = str:match "^'?(.-)'?$" -- remove single quotes
  str = str:gsub("file://", "") -- remove "file://"
  str = str:gsub("%c", "") -- remove control characters

  return str
end

---@param str string
---@return boolean
---@return string?
local is_remote = function(str)
  -- return early if not a valid url to a subdomain
  if not str:match "^https?://[^/]+/[^.]+" then
    return false
  end

  -- assume its a valid image link if it the url ends with an extension
  for _, ext in ipairs(ft) do
    local pattern = "%." .. ext .. "$"

    local before_pat = "%." .. ext .. "%?"
    if str:match(pattern) or str:match(before_pat) then
      return true, ext
    end
  end

  return false

  -- send a head request to the url and check content type
  -- local cmd = { "curl", "-s", "-I", "-w", "%%{content_type}", str }
  -- local obj = vim.system(cmd):wait()
  -- local output, exit_code = obj.stdout, obj.code
  -- return exit_code == 0 and output ~= nil and (output:match "image/png" ~= nil or output:match "image/jpeg" ~= nil)
end

---@param str string
---@return boolean
---@return string?
local is_local = function(str)
  str = string.lower(str)

  --- TODO: correct path sep
  local has_path_sep = str:find "/" ~= nil or str:find "\\" ~= nil

  if not has_path_sep then
    return false
  end

  -- assume its a valid link if it the url ends with an extension
  for _, ext in ipairs(ft) do
    local end_pat = "%." .. ext .. "$"
    if str:match(end_pat) then
      return true, ext
    end
  end
end

---@param client obsidian.Client
---@param path string
---@param ext string?
---@return boolean
---@return string
local function drop_local(client, path, ext)
  local from = vim.fs.abspath(path):gsub("\\", "")

  local dst = client.opts.attachments.file_path_func(client, path, ext, false)

  -- TODO: obsidian has option to hold Ctrl to just link instead of copying
  local copy_ok, err = vim.uv.fs_copyfile(from, tostring(dst))
  if not copy_ok then
    vim.notify(err or "failed to copy file", 3)
    return false
  end
  vim.notify("Copied file to " .. tostring(dst))
  return true, dst
end

local drop_remote = function(client, url, ext)
  local dst = client.opts.attachments.file_path_func(client, url, ext, true)

  dst = tostring(dst)

  local obj = vim.system({ "curl", url, "-o", dst }, {}):wait()

  if obj.code == 0 then
    vim.notify("file " .. dst .. " saved")
    return true, dst
  else
    vim.notify("file " .. dst .. " failed to save")
    return false
  end
end

---@param client obsidian.Client
---@param input string
---@return boolean
local function try_drop(client, input)
  input = sanitize_input(input)

  local ok, link, ext, remote, loc
  remote, ext = is_remote(input)
  loc, ext = is_local(input)

  if remote then
    ok, link = drop_remote(client, input, ext)
  elseif loc then
    ok, link = drop_local(client, input, ext)
  else
    return false
  end

  if ok then
    insert_link(client, link)
    return true
  else
    return false
  end
end

-- TODO: do more checks
return {
  register = function(og_paste)
    return function(lines, phase)
      local line = lines[1]

      -- probably not a file path or url to an image if the input is this long
      if string.len(line) > 512 then
        return og_paste(lines, phase)
      end

      local ok = try_drop(require("obsidian").get_client(), line)

      if not ok then
        vim.notify "Did not handle paste, calling original vim.paste"
        return og_paste(lines, phase)
      end
    end
  end,
}
