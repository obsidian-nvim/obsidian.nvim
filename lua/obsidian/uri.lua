local M = {}

local function char_to_hex(c)
  return string.format("%%%02X", string.byte(c))
end

--- Encode a string for use in a URL.
---@param str string
---@param opts? { keep_path_sep?: boolean }
---@return string
M.encode = function(str, opts)
  opts = opts or {}
  local url = str:gsub("\n", "\r\n")
  url = url:gsub("([%(%)%*%?%[%]%$\"':<>|\\'{}&])", char_to_hex)
  if not opts.keep_path_sep then
    url = url:gsub("/", char_to_hex)
  end
  url = url:gsub(" ", "%%20")
  return url
end

--- Return a URI's normalized scheme. Windows drive paths are not URIs.
---@param value string
---@return string? scheme
M.scheme = function(value)
  local scheme, rest = value:match "^([%a][%w+%-%.]*):(.*)$"
  if not scheme or not rest then
    return nil
  end
  if #scheme == 1 and rest:match "^[\\/]." then
    return nil
  end
  return scheme:lower()
end

---@param value string
---@return boolean is_uri
---@return string? scheme
M.is_uri = function(value)
  local scheme = M.scheme(value)
  return scheme ~= nil, scheme
end

return M
