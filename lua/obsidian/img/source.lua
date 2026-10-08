local Path = require "obsidian.path"

local M = {}

local png_signature = "\137PNG\r\n\26\n"

local function be32(bytes, offset)
  local a, b, c, d = bytes:byte(offset, offset + 3)
  if not d then
    return nil
  end
  return ((a * 256 + b) * 256 + c) * 256 + d
end

---@param bytes string
---@return { width: integer, height: integer }|nil
---@return string|nil
function M.png_info(bytes)
  if type(bytes) ~= "string" or #bytes < 33 then
    return nil, "truncated PNG"
  end
  if bytes:sub(1, 8) ~= png_signature then
    return nil, "not a PNG image"
  end
  if be32(bytes, 9) ~= 13 or bytes:sub(13, 16) ~= "IHDR" then
    return nil, "invalid PNG header"
  end

  local width = be32(bytes, 17)
  local height = be32(bytes, 21)
  if not width or not height or width < 1 or height < 1 then
    return nil, "invalid PNG dimensions"
  end
  return { width = width, height = height }
end

local function schedule(callback, ...)
  local args = vim.F.pack_len(...)
  vim.schedule(function()
    callback(unpack(args, 1, args.n))
  end)
end

---@alias obsidian.img.Source string|{ path: string }|{ bytes: string, name: string? }

---Read and validate a local PNG without blocking the main loop.
---@param source obsidian.img.Source
---@param callback fun(result: { bytes: string, width: integer, height: integer, path: string? }|nil, err: string|nil)
function M.load(source, callback)
  if type(source) == "table" and source.bytes ~= nil then
    if type(source.bytes) ~= "string" then
      schedule(callback, nil, "image bytes must be a string")
      return
    end
    local info, err = M.png_info(source.bytes)
    if not info then
      schedule(callback, nil, err)
      return
    end
    schedule(callback, {
      bytes = source.bytes,
      width = info.width,
      height = info.height,
    }, nil)
    return
  end

  local path = type(source) == "table" and source.path or source
  if type(path) ~= "string" or path == "" then
    schedule(callback, nil, "image source must contain a path or PNG bytes")
    return
  end
  path = vim.fs.normalize(path)
  if not Path.new(path):is_absolute() then
    schedule(callback, nil, "image path must be absolute")
    return
  end

  vim.uv.fs_stat(path, function(stat_err, stat)
    if stat_err or not stat then
      schedule(callback, nil, "image does not exist: " .. path)
      return
    elseif stat.type ~= "file" then
      schedule(callback, nil, "image source is not a file: " .. path)
      return
    end

    vim.uv.fs_open(path, "r", 438, function(open_err, fd)
      if open_err or not fd then
        schedule(callback, nil, "failed to open image: " .. path)
        return
      end
      vim.uv.fs_read(fd, stat.size, 0, function(read_err, bytes)
        vim.uv.fs_close(fd, function() end)
        if read_err or type(bytes) ~= "string" or #bytes ~= stat.size then
          schedule(callback, nil, "failed to read image: " .. path)
          return
        end
        local info, info_err = M.png_info(bytes)
        if not info then
          schedule(callback, nil, info_err .. ": " .. path)
          return
        end
        schedule(callback, {
          bytes = bytes,
          width = info.width,
          height = info.height,
          path = path,
        }, nil)
      end)
    end)
  end)
end

return M
