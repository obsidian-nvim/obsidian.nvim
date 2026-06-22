--- Minimal JSON Canvas view for obsidian.nvim.
---
--- Serves a local browser UI for `.canvas` files using the JSON Canvas 1.0
--- document shape: https://jsoncanvas.org/spec/1.0/

local HttpServer = require "obsidian.web.server"
local Path = require "obsidian.path"

local uv = vim.uv

local M = {}

---@return string
local function make_token()
  return vim.fn.sha256(tostring(uv.hrtime()) .. tostring(math.random()) .. tostring {})
end

---@param client uv_tcp_t
---@param status string
---@param content_type string
---@param body string
local function respond(client, status, content_type, body)
  HttpServer.respond(client, status, content_type, body)
end

---@param path string|obsidian.Path
---@param mode string?
---@return string
local function read_file(path, mode)
  local f = assert(io.open(tostring(path), mode or "r"))
  local body = f:read "*a"
  f:close()
  return body or ""
end

---@param value any
---@return boolean
local function is_list(value)
  return type(value) == "table" and vim.islist(value)
end

---@param canvas any
---@return boolean success
---@return string? err
local function validate_canvas(canvas)
  if type(canvas) ~= "table" then
    return false, "Canvas must be a JSON object"
  end
  if canvas.nodes ~= nil and not is_list(canvas.nodes) then
    return false, "Canvas 'nodes' must be an array"
  end
  if canvas.edges ~= nil and not is_list(canvas.edges) then
    return false, "Canvas 'edges' must be an array"
  end

  canvas.nodes = canvas.nodes or {}
  canvas.edges = canvas.edges or {}

  for i, node in ipairs(canvas.nodes) do
    if type(node) ~= "table" then
      return false, "Node " .. i .. " must be an object"
    end
    if type(node.id) ~= "string" or node.id == "" then
      return false, "Node " .. i .. " must have a string id"
    end
    if type(node.type) ~= "string" or node.type == "" then
      return false, "Node " .. node.id .. " must have a string type"
    end
  end

  for i, edge in ipairs(canvas.edges) do
    if type(edge) ~= "table" then
      return false, "Edge " .. i .. " must be an object"
    end
    if type(edge.id) ~= "string" or edge.id == "" then
      return false, "Edge " .. i .. " must have a string id"
    end
    if type(edge.fromNode) ~= "string" or edge.fromNode == "" then
      return false, "Edge " .. edge.id .. " must have a string fromNode"
    end
    if type(edge.toNode) ~= "string" or edge.toNode == "" then
      return false, "Edge " .. edge.id .. " must have a string toNode"
    end
  end

  return true
end

---@param path string|obsidian.Path
---@return table? canvas
---@return string? err
function M.read_canvas(path)
  local ok, body = pcall(read_file, path)
  if not ok then
    return nil, "Failed to read canvas: " .. tostring(body)
  end

  if vim.trim(body) == "" then
    return { nodes = {}, edges = {} }
  end

  local decoded_ok, canvas = pcall(vim.json.decode, body)
  if not decoded_ok then
    return nil, "Invalid JSON: " .. tostring(canvas)
  end

  local valid, err = validate_canvas(canvas)
  if not valid then
    return nil, err
  end

  return canvas
end

---@param path string|obsidian.Path
---@param canvas table
---@return boolean success
---@return string? err
function M.write_canvas(path, canvas)
  local valid, err = validate_canvas(canvas)
  if not valid then
    return false, err
  end

  local ok, body = pcall(vim.json.encode, canvas)
  if not ok then
    return false, "Failed to encode canvas: " .. tostring(body)
  end
  body = body .. "\n"
  local lines = vim.split(body, "\n", { plain = true })
  if lines[#lines] == "" then
    table.remove(lines)
  end

  local write_ok, write_result = pcall(vim.fn.writefile, lines, tostring(path))
  if not write_ok or write_result ~= 0 then
    return false, "Failed to write canvas: " .. tostring(write_result)
  end

  vim.schedule(function()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if
        vim.api.nvim_buf_is_loaded(bufnr)
        and vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr)) == vim.fs.normalize(tostring(path))
      then
        if vim.bo[bufnr].modified then
          vim.notify("Canvas saved on disk; buffer has unsaved changes", vim.log.levels.WARN)
        else
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
          vim.bo[bufnr].modified = false
        end
      end
    end
  end)

  return true
end

---@return string
local function canvas_page()
  local body = (require "obsidian.core-plugins.canvas.web"):gsub("__OBSIDIAN_CANVAS_TOKEN__", M._token or "")
  return body
end

---@param req obsidian.web.Request
---@return string?
local function request_canvas_path(req)
  local path = req.params.path or M._file
  if type(path) ~= "string" or path == "" then
    return nil
  end
  return vim.fs.normalize(path)
end

---@param client uv_tcp_t
---@param path string?
local function respond_canvas(client, path)
  if not path then
    respond(client, "400 Bad Request", "text/plain", "Missing canvas path")
    return
  end

  local canvas, err = M.read_canvas(path)
  if not canvas then
    respond(client, "400 Bad Request", "text/plain", err or "Invalid canvas")
    return
  end

  respond(client, "200 OK", "application/json", vim.json.encode(canvas))
end

---@param client uv_tcp_t
---@param path string?
---@param req obsidian.web.Request
local function save_canvas(client, path, req)
  if not path then
    respond(client, "400 Bad Request", "text/plain", "Missing canvas path")
    return
  end

  local ok, canvas = pcall(vim.json.decode, req.body or "")
  if not ok then
    respond(client, "400 Bad Request", "text/plain", "Invalid JSON: " .. tostring(canvas))
    return
  end

  vim.schedule(function()
    local success, err = M.write_canvas(path, canvas)
    if not success then
      respond(client, "400 Bad Request", "text/plain", err or "Invalid canvas")
      return
    end

    respond(client, "200 OK", "application/json", vim.json.encode { ok = true })
  end)
end

---@param path string
---@return string?
local function vault_path(path)
  if not Obsidian or not Obsidian.dir then
    return nil
  end
  local candidate = Obsidian.dir / path
  if candidate:exists() then
    return tostring(candidate)
  end
end

---@param base string
---@param file string
---@return string
local function resolve_file_node(base, file)
  if Path.new(file):is_absolute() then
    return vim.fs.normalize(file)
  end

  local from_vault = vault_path(file)
  if from_vault then
    return from_vault
  end

  return tostring(Path.new(base):parent() / file)
end

---@param path string
---@return string
local function file_content_type(path)
  local ext = (path:match "%.([^./\\]+)$" or ""):lower()
  return ({
    png = "image/png",
    jpg = "image/jpeg",
    jpeg = "image/jpeg",
    gif = "image/gif",
    webp = "image/webp",
    svg = "image/svg+xml",
    avif = "image/avif",
    bmp = "image/bmp",
    ico = "image/x-icon",
    pdf = "application/pdf",
    md = "text/markdown; charset=utf-8",
    markdown = "text/markdown; charset=utf-8",
    txt = "text/plain; charset=utf-8",
    lua = "text/plain; charset=utf-8",
    json = "application/json; charset=utf-8",
    mp3 = "audio/mpeg",
    wav = "audio/wav",
    ogg = "audio/ogg",
    flac = "audio/flac",
    m4a = "audio/mp4",
    mp4 = "video/mp4",
    webm = "video/webm",
    mov = "video/quicktime",
  })[ext] or "application/octet-stream"
end

---@param client uv_tcp_t
---@param req obsidian.web.Request
local function serve_file_node(client, req)
  local file = req.params.file
  if type(file) ~= "string" or file == "" then
    respond(client, "400 Bad Request", "text/plain", "Missing file")
    return
  end
  if file:match "^[%w+.-]+:" then
    respond(client, "400 Bad Request", "text/plain", "Cannot serve URI file nodes")
    return
  end

  local canvas_path = request_canvas_path(req) or M._file or ""
  local path = resolve_file_node(canvas_path, file)
  if vim.uv.fs_stat(path) == nil then
    respond(client, "404 Not Found", "text/plain", "File not found")
    return
  end

  local ok, body = pcall(read_file, path, "rb")
  if not ok then
    respond(client, "500 Internal Server Error", "text/plain", "Failed to read file: " .. tostring(body))
    return
  end

  respond(client, "200 OK", file_content_type(path), body)
end

---@param subpath string?
local function jump_to_subpath(subpath)
  if type(subpath) ~= "string" or subpath == "" then
    return
  end

  if vim.startswith(subpath, "#") then
    local heading = vim.pesc(vim.trim(subpath:sub(2)))
    if heading ~= "" then
      vim.fn.search("^#\\+\\s\\+" .. heading .. "\\s*$", "w")
    end
  end
end

---@param client uv_tcp_t
---@param req obsidian.web.Request
local function open_file_node(client, req)
  local ok, payload = pcall(vim.json.decode, req.body or "")
  if not ok or type(payload) ~= "table" then
    respond(client, "400 Bad Request", "text/plain", "Invalid JSON")
    return
  end

  local file = payload.file
  if type(file) ~= "string" or file == "" then
    respond(client, "400 Bad Request", "text/plain", "Missing file")
    return
  end

  if file:match "^[%w+.-]+:" then
    vim.schedule(function()
      vim.ui.open(file)
    end)
    respond(client, "200 OK", "application/json", vim.json.encode { ok = true })
    return
  end

  local canvas_path = request_canvas_path(req) or M._file or ""
  local path = resolve_file_node(canvas_path, file)
  local cmd = ({ split = "split", vsplit = "vsplit", tab = "tabedit" })[payload.open or "edit"] or "edit"

  vim.schedule(function()
    vim.cmd(cmd .. " " .. vim.fn.fnameescape(path))
    jump_to_subpath(payload.subpath)
  end)

  respond(client, "200 OK", "application/json", vim.json.encode { ok = true })
end

---@param client uv_tcp_t
---@param req obsidian.web.Request
local function handle_request(client, req)
  if req.path == "/api/canvas" and req.params.token ~= M._token then
    respond(client, "403 Forbidden", "text/plain", "Forbidden")
    return
  end
  if req.path == "/api/open" and req.params.token ~= M._token then
    respond(client, "403 Forbidden", "text/plain", "Forbidden")
    return
  end
  if req.path == "/api/file" and req.params.token ~= M._token then
    respond(client, "403 Forbidden", "text/plain", "Forbidden")
    return
  end

  if (req.path == "/" or req.path == "/index.html") and req.method == "GET" then
    respond(client, "200 OK", "text/html; charset=utf-8", canvas_page())
  elseif req.path == "/api/canvas" and req.method == "GET" then
    respond_canvas(client, request_canvas_path(req))
  elseif req.path == "/api/canvas" and req.method == "POST" then
    save_canvas(client, request_canvas_path(req), req)
  elseif req.path == "/api/open" and req.method == "POST" then
    open_file_node(client, req)
  elseif req.path == "/api/file" and req.method == "GET" then
    serve_file_node(client, req)
  elseif req.method ~= "GET" and req.method ~= "POST" then
    respond(client, "405 Method Not Allowed", "text/plain", "Method not allowed")
  else
    respond(client, "404 Not Found", "text/plain", "Not found")
  end
end

--- Start the canvas HTTP server on the given port.
---@param port integer
---@return boolean success
function M.start_server(port)
  local server = HttpServer.new {
    port = port,
    on_error = function(err)
      vim.notify("Canvas server error: " .. tostring(err), vim.log.levels.ERROR)
    end,
    on_request = function(_, client, req)
      handle_request(client, req)
    end,
  }

  if not server:start() then
    return false
  end

  M._server = server
  M._port = server.port
  M._token = make_token()
  return true
end

function M.stop_server()
  if M._server then
    M._server:stop()
    M._server = nil
    M._port = nil
    M._token = nil
    M._file = nil
  end
end

---@param path string
---@return boolean
function M.open_file(path)
  path = vim.fs.normalize(path)
  M._file = path

  local url_path = "/?path=" .. vim.uri_encode(path)
  if M._server then
    vim.ui.open(M._server:url(url_path))
    return true
  end

  for port = 49886, 49895 do
    if M.start_server(port) then
      local url = M._server:url(url_path)
      vim.notify("Canvas view at " .. url)
      vim.ui.open(url)
      return true
    end
  end

  vim.notify("Failed to start canvas server (ports 49886-49895 busy)", vim.log.levels.ERROR)
  return false
end

---@param bufnr integer?
---@return boolean
function M.open_current(bufnr)
  bufnr = bufnr or 0
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" or not vim.endswith(path, ".canvas") then
    vim.notify("Current buffer is not a .canvas file", vim.log.levels.ERROR)
    return false
  end

  return M.open_file(path)
end

return M
