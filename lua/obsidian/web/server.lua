local uv = vim.uv

---@class obsidian.web.Request
---@field method string|nil
---@field raw_path string
---@field path string
---@field query string
---@field params table<string, string>
---@field headers table<string, string>
---@field body string
---@field raw string

---@class obsidian.web.ServerOpts
---@field host string|nil
---@field port integer
---@field backlog integer|nil
---@field max_request_bytes integer|nil
---@field on_request fun(server: obsidian.web.Server, client: any, req: obsidian.web.Request)
---@field on_error fun(err: string)|nil

---@class obsidian.web.Server
---@field host string
---@field port integer
---@field backlog integer
---@field max_request_bytes integer
---@field on_request fun(server: obsidian.web.Server, client: any, req: obsidian.web.Request)
---@field on_error fun(err: string)|nil
---@field _handle any|nil
local Server = {}

Server.__index = Server

local DEFAULT_MAX_REQUEST_BYTES = 1024 * 1024

---@param client any
function Server.close_client(client)
  if client and not client:is_closing() then
    pcall(function()
      client:close()
    end)
  end
end

---Serve a single HTTP response.
---@param client any
---@param status string e.g. "200 OK"
---@param content_type string
---@param body string
function Server.respond(client, status, content_type, body)
  local header = string.format(
    "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n",
    status,
    content_type,
    #body
  )

  client:write(header .. body, function()
    if not client:is_closing() then
      client:shutdown(function()
        Server.close_client(client)
      end)
    end
  end)
end

---@param client any
---@param value any
function Server.respond_json(client, value)
  Server.respond(client, "200 OK", "application/json", vim.json.encode(value))
end

---@param request string
---@return boolean
function Server.request_complete(request)
  local header_start, header_end = request:find("\r\n\r\n", 1, true)
  if not header_end then
    header_start, header_end = request:find("\n\n", 1, true)
  end
  if not header_end then
    return false
  end

  ---@cast header_start integer
  local head = request:sub(1, header_start - 1)
  local content_length = tonumber(head:lower():match "content%-length:%s*(%d+)") or 0
  return #request >= header_end + content_length
end

---@param request string
---@return obsidian.web.Request req
function Server.parse_request(request)
  local header_start, header_end = request:find("\r\n\r\n", 1, true)
  if not header_end then
    header_start, header_end = request:find("\n\n", 1, true)
  end
  if not header_end then
    return {
      method = nil,
      raw_path = "/",
      path = "/",
      query = "",
      params = {},
      headers = {},
      body = request,
      raw = request,
    }
  end
  ---@cast header_start integer
  ---@cast header_end integer

  local head = request:sub(1, header_start - 1)
  local body = request:sub(header_end + 1)
  local lines = vim.split(head, "\n", { plain = true })
  for i, line in ipairs(lines) do
    lines[i] = line:gsub("\r$", "")
  end
  local method, raw_path
  if lines[1] then
    method, raw_path = lines[1]:match "^(%S+)%s+(%S+)"
  end
  raw_path = raw_path or "/"
  local headers = {}

  for i = 2, #lines do
    local key, value = lines[i]:match "^([^:]+):%s*(.*)$"
    if key then
      headers[key:lower()] = value
    end
  end

  local path, query = raw_path:match "^([^?]*)%??(.*)$"
  path = path or ""
  query = query or ""
  local params = {}
  for pair in (query or ""):gmatch "[^&]+" do
    local key, value = pair:match "^([^=]*)=?(.*)$"
    if key and key ~= "" then
      params[vim.uri_decode(key)] = vim.uri_decode(value or "")
    end
  end

  return {
    method = method,
    raw_path = raw_path,
    path = path,
    query = query,
    params = params,
    headers = headers,
    body = body,
    raw = request,
  }
end

---@param opts obsidian.web.ServerOpts
---@return obsidian.web.Server
Server.new = function(opts)
  return setmetatable({
    host = opts.host or "127.0.0.1",
    port = opts.port,
    backlog = opts.backlog or 128,
    max_request_bytes = opts.max_request_bytes or DEFAULT_MAX_REQUEST_BYTES,
    on_request = opts.on_request,
    on_error = opts.on_error,
  }, Server)
end

---@return boolean success
---@return string? err
function Server:start()
  if self._handle then
    return true
  end

  local handle = uv.new_tcp()
  if not handle then
    return false, "failed to create TCP handle"
  end

  local ok, err = handle:bind(self.host, self.port)
  if not ok then
    handle:close()
    return false, err
  end

  ok, err = handle:listen(self.backlog, function(listen_err)
    if listen_err then
      if self.on_error then
        self.on_error(tostring(listen_err))
      end
      return
    end

    local client = uv.new_tcp()
    if not client then
      return
    end

    handle:accept(client)

    local chunks = {}
    local request_size = 0
    client:read_start(function(read_err, data)
      if read_err then
        Server.close_client(client)
        return
      end
      if not data then
        return
      end

      request_size = request_size + #data
      if request_size > self.max_request_bytes then
        client:read_stop()
        Server.respond(client, "413 Payload Too Large", "text/plain", "Request too large")
        return
      end

      chunks[#chunks + 1] = data
      local request = table.concat(chunks)
      if Server.request_complete(request) then
        client:read_stop()
        self.on_request(self, client, Server.parse_request(request))
      end
    end)
  end)

  if not ok then
    handle:close()
    return false, err
  end

  -- Do not keep headless Neovim alive just because the server is open.
  handle:unref()

  self._handle = handle
  local sockname_ok, sockname = pcall(function()
    return handle:getsockname()
  end)
  if sockname_ok and sockname and sockname.port then
    self.port = sockname.port
  end

  return true
end

function Server:stop()
  if self._handle then
    self._handle:close()
    self._handle = nil
  end
end

---@return boolean
function Server:is_running()
  return self._handle ~= nil and not self._handle:is_closing()
end

---@param path string|nil
---@return string
function Server:url(path)
  return "http://" .. self.host .. ":" .. self.port .. (path or "")
end

return Server
