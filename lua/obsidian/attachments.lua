-- accpeted file formats: https://help.obsidian.md/file-formats

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

local m_filetype = {}

for _, v in ipairs(filetypes) do
  m_filetype[v] = true
end

local function supports_extension(path)
  local basename = vim.fs.basename(path)
  local ext = basename:match "^.+%.(.+)$"
  return m_filetype[ext], basename
end

local function insert_link(client, dst)
  local new_link = "!" .. client:format_link(dst)
  vim.api.nvim_put({ new_link }, "l", true, true)
end

local function drop_local_file(line)
  local from = vim.fs.abspath(line):gsub("\\", "")
  local support, base = supports_extension(from)

  if support then
    local Path = require "obsidian.path"
    local client = require("obsidian").get_client()
    local dst = (Path.new(client.dir) / client.opts.attachments.img_folder / base):resolve()

    local copy_ok, err = vim.uv.fs_copyfile(from, tostring(dst))
    if not copy_ok then
      vim.notify(err or "failed to copy file", 3)
      return false
    end
    insert_link(client, dst)
    vim.notify("Copied file to " .. tostring(dst))
    return true
  else
    vim.notify("file extension not supported", 3)
    return false
  end
end

local drop_remote_file = function(url)
  local Path = require "obsidian.path"
  local client = require("obsidian").get_client()
  local base = client.opts.attachments.img_name_func()

  local dst = (Path.new(client.dir) / client.opts.attachments.img_folder / base):resolve()
  dst = tostring(dst)

  local obj = vim.system({ "curl", url, "-o", dst }, {}):wait()

  if obj.code == 0 then
    vim.notify("file " .. dst .. " saved")
    insert_link(client, dst)
    return true
  else
    vim.notify("file " .. dst .. " failed to save")
    return false
  end
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
local is_image_url = function(str)
  -- return early if not a valid url to a subdomain
  if not str:match "^https?://[^/]+/[^.]+" then
    return false
  end

  -- assume its a valid image link if it the url ends with an extension
  if str:match "%.png$" or str:match "%.jpg$" or str:match "%.jpeg$" then
    return true
  end

  -- send a head request to the url and check content type
  local cmd = { "curl", "-s", "-I", "-w", "%%{content_type}", str }
  local obj = vim.system(cmd):wait()
  local output, exit_code = obj.stdout, obj.code
  return exit_code == 0 and output ~= nil and (output:match "image/png" ~= nil or output:match "image/jpeg" ~= nil)
end

---@param str string
---@return boolean
local is_image_path = function(str)
  str = string.lower(str)

  local has_path_sep = str:find "/" ~= nil or str:find "\\" ~= nil
  local has_image_ext = str:match "^.*%.(png)$" ~= nil
    or str:match "^.*%.(jpg)$" ~= nil
    or str:match "^.*%.(jpeg)$" ~= nil

  return has_path_sep and has_image_ext
end

local function handle(input)
  input = sanitize_input(input)

  if is_image_url(input) then
    print "here"
    return drop_remote_file(input)
  elseif is_image_path(input) then
    return drop_local_file(input)
  end

  return false
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

      local ok = handle(line)

      if not ok then
        vim.notify "Did not handle paste, calling original vim.paste"
        return og_paste(lines, phase)
      end
    end
  end,
}
