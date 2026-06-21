--- Minimal local graph view for obsidian.nvim.
---
--- Scans markdown notes in the active vault, extracts internal links, and serves a
--- small browser UI from a local HTTP server.

local ignore = require "obsidian.ignore"
local Path = require "obsidian.path"
local refs = require "obsidian.parse.refs"

local uv = vim.uv or vim.loop

local M = {}

local function strip_markdown_suffix(path)
  return path:gsub("%.markdown$", ""):gsub("%.md$", "")
end

---@return string|?
function M.current_note_id()
  local ok, rel = pcall(function()
    return Path.buffer(0):vault_relative_path { strict = true }
  end)
  if not ok or not rel then
    return nil
  end

  local id = strip_markdown_suffix(tostring(rel))
  if id == tostring(rel) then
    return nil
  end
  return id
end

local function normalize_target(target)
  target = vim.trim(target or "")
  if target == "" or target:sub(1, 1) == "#" then
    return nil
  end
  if target:match "^[%w+.-]+:" then
    return nil
  end

  target = target:gsub("\\", "/")
  target = target:gsub("^%./", "")
  target = target:gsub("^/", "")

  local ok, decoded = pcall(vim.uri_decode, target)
  if ok then
    target = decoded
  end

  return strip_markdown_suffix(target)
end

--- Collect all markdown notes in the vault recursively.
---@return obsidian.Path[]
function M.find_notes()
  local files = {}

  local function walk(dir)
    local h = uv.fs_scandir(dir)
    if not h then
      return
    end

    while true do
      local name, type = uv.fs_scandir_next(h)
      if not name then
        break
      end

      local full = Path.new(dir) / name
      if type == "directory" then
        if not vim.startswith(name, ".") and name ~= "node_modules" and not ignore.is_ignored(tostring(full)) then
          walk(tostring(full))
        end
      elseif
        type == "file"
        and (name:match "%.md$" or name:match "%.markdown$")
        and not ignore.is_ignored(tostring(full))
      then
        files[#files + 1] = full
      end
    end
  end

  walk(tostring(Obsidian.dir))
  table.sort(files, function(a, b)
    return tostring(a) < tostring(b)
  end)

  return files
end

--- Extract internal link targets from a note.
---@param path obsidian.Path
---@return string[]
function M.extract_links(path)
  local links = {}
  local f = io.open(tostring(path), "r")
  if not f then
    return links
  end

  for line in f:lines() do
    for _, ref in ipairs(refs.extract(line)) do
      if ref.kind ~= "footnote" then
        local target = normalize_target(ref.target)
        if target then
          links[#links + 1] = target
        end
      end
    end
  end

  f:close()
  return links
end

---@param target string
---@param target_to_id table<string, string|false>
---@return string|?
local function resolve_target(target, target_to_id)
  local id = target_to_id[target]
  if id then
    return id
  end

  -- Obsidian wiki links often omit folders. If the target includes a folder,
  -- try the basename too. Ambiguous basenames are stored as false and ignored.
  local basename = target:match "([^/]+)$"
  id = basename and target_to_id[basename] or nil
  if id then
    return id
  end
end

--- Build graph data: note nodes and note-to-note links.
---@return table graph { nodes: {id:string, title:string, path:string}[], links: {source:string, target:string}[] }
function M.build_graph()
  local files = M.find_notes()
  local target_to_id = {}
  local nodes = {}
  local links = {}
  local link_set = {}

  for _, filepath in ipairs(files) do
    local rel = filepath:vault_relative_path { strict = true }
    local id = strip_markdown_suffix(tostring(rel))
    local stem = filepath.stem

    nodes[#nodes + 1] = { id = id, title = stem, path = tostring(filepath) }
    target_to_id[id] = id

    if target_to_id[stem] == nil then
      target_to_id[stem] = id
    elseif target_to_id[stem] ~= id then
      target_to_id[stem] = false
    end
  end

  for _, filepath in ipairs(files) do
    local rel = filepath:vault_relative_path { strict = true }
    local source = strip_markdown_suffix(tostring(rel))

    for _, target in ipairs(M.extract_links(filepath)) do
      local resolved = resolve_target(target, target_to_id)
      if resolved and resolved ~= source then
        local key = source .. "\0" .. resolved
        if not link_set[key] then
          link_set[key] = true
          links[#links + 1] = { source = source, target = resolved }
        end
      end
    end
  end

  return { nodes = nodes, links = links }
end

---@return string
local function make_token()
  return vim.fn.sha256(tostring(uv.hrtime()) .. tostring(math.random()) .. tostring {})
end

---@param client uv_tcp_t
local function close_client(client)
  if client and not client:is_closing() then
    pcall(function()
      client:close()
    end)
  end
end

--- Serve a single HTTP response.
---@param client uv_tcp_t
---@param status string e.g. "200 OK"
---@param content_type string
---@param body string
local function respond(client, status, content_type, body)
  local header = string.format(
    "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n",
    status,
    content_type,
    #body
  )

  client:write(header .. body, function()
    if not client:is_closing() then
      client:shutdown(function()
        close_client(client)
      end)
    end
  end)
end

---@param request string
---@return boolean
local function request_complete(request)
  local header_start, header_end = request:find("\r\n\r\n", 1, true)
  if not header_end then
    header_start, header_end = request:find("\n\n", 1, true)
  end
  if not header_end then
    return false
  end

  local head = request:sub(1, header_start - 1)
  local content_length = tonumber(head:match "[Cc]ontent%-[Ll]ength:%s*(%d+)") or 0
  return #request >= header_end + content_length
end

---@param request string
---@return table req
local function parse_request(request)
  local header_start, header_end = request:find("\r\n\r\n", 1, true)
  if not header_end then
    header_start, header_end = request:find("\n\n", 1, true)
  end

  local head = request:sub(1, header_start - 1)
  local body = request:sub(header_end + 1)
  local lines = vim.split(head, "\n", { plain = true })
  for i, line in ipairs(lines) do
    lines[i] = line:gsub("\r$", "")
  end
  local method, raw_path = lines[1]:match "^(%S+)%s+(%S+)"
  raw_path = raw_path or "/"
  local headers = {}

  for i = 2, #lines do
    local key, value = lines[i]:match "^([^:]+):%s*(.*)$"
    if key then
      headers[key:lower()] = value
    end
  end

  local path, query = raw_path:match "^([^?]*)%??(.*)$"
  local params = {}
  for pair in (query or ""):gmatch "[^&]+" do
    local key, value = pair:match "^([^=]*)=?(.*)$"
    if key and key ~= "" then
      params[vim.uri_decode(key)] = vim.uri_decode(value or "")
    end
  end

  return { method = method, path = path, query = query, params = params, headers = headers, body = body }
end

---@return string
local function graph_page()
  local body = (require "obsidian.core-plugins.graph.web"):gsub("__OBSIDIAN_GRAPH_TOKEN__", M._token or "")
  return body
end

---@param id string
---@return string|?
function M.note_path_by_id(id)
  if type(id) ~= "string" or id == "" then
    return nil
  end

  for _, node in ipairs(M.build_graph().nodes) do
    if node.id == id then
      return node.path
    end
  end
end

---@param id string
---@param open string?
---@return boolean success
---@return string? err
function M.open_note_by_id(id, open)
  local path = M.note_path_by_id(id)
  if not path then
    return false, "note not found"
  end

  local commands = {
    edit = "edit",
    split = "split",
    vsplit = "vsplit",
    tab = "tabedit",
  }
  local cmd = commands[open or "edit"] or "edit"

  vim.schedule(function()
    require("obsidian.api").open_note({ filename = path }, cmd)
  end)

  return true
end

---@param client uv_tcp_t
---@param event table
local function send_sse(client, event)
  if not client or client:is_closing() then
    return
  end

  local ok, data = pcall(vim.json.encode, event)
  if not ok then
    return
  end

  client:write("event: message\ndata: " .. data .. "\n\n", function(err)
    if err then
      if M._sse_clients then
        M._sse_clients[client] = nil
      end
      close_client(client)
    end
  end)
end

---@param event table
function M.broadcast(event)
  if not M._sse_clients then
    return
  end

  for client in pairs(M._sse_clients) do
    send_sse(client, event)
  end
end

---@param reason string?
function M.broadcast_graph_update(reason)
  if not M._sse_clients or not next(M._sse_clients) then
    return
  end

  local ok, graph = pcall(M.build_graph)
  if ok then
    M.broadcast { type = "graph:update", graph = graph, reason = reason }
  end
end

---@param reason string?
function M.schedule_graph_update(reason)
  if M._graph_update_timer then
    M._graph_update_timer:stop()
  else
    M._graph_update_timer = uv.new_timer()
    if M._graph_update_timer then
      M._graph_update_timer:unref()
    end
  end

  if not M._graph_update_timer then
    vim.schedule(function()
      M.broadcast_graph_update(reason)
    end)
    return
  end

  M._graph_update_timer:start(150, 0, function()
    vim.schedule(function()
      M.broadcast_graph_update(reason)
    end)
  end)
end

function M.broadcast_current_note()
  local id = M.current_note_id()
  if not id then
    return
  end

  M.broadcast { type = "active:set", id = id }
  M.broadcast { type = "local:set_root", id = id }
end

local function ensure_live_hooks()
  if M._live_hooks_started then
    return
  end

  M._sse_clients = M._sse_clients or {}
  M._unregister_watchfiles = require("obsidian.lsp.watchfiles").register_handler(function(events)
    local FileChangeType = vim.lsp.protocol.FileChangeType
    for _, event in ipairs(events) do
      if event.type == FileChangeType.Created or event.type == FileChangeType.Deleted then
        M.schedule_graph_update "files"
        return
      end
    end
  end)

  M._augroup = vim.api.nvim_create_augroup("obsidian_graph_live", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = M._augroup,
    pattern = "ObsidianNoteEnter",
    callback = function()
      M.broadcast_current_note()
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = M._augroup,
    pattern = "ObsidianNoteWritePost",
    callback = function()
      M.schedule_graph_update "write"
    end,
  })

  M._live_hooks_started = true
end

---@param client uv_tcp_t
local function respond_events(client)
  local header = table.concat({
    "HTTP/1.1 200 OK",
    "Content-Type: text/event-stream",
    "Cache-Control: no-cache",
    "Connection: keep-alive",
    "Access-Control-Allow-Origin: *",
    "",
    "",
  }, "\r\n")

  M._sse_clients = M._sse_clients or {}
  M._sse_clients[client] = true
  client:write(header)
  client:unref()

  send_sse(client, { type = "graph:update", graph = M.build_graph(), reason = "connect" })
  local id = M.current_note_id()
  if id then
    send_sse(client, { type = "active:set", id = id })
    send_sse(client, { type = "local:set_root", id = id })
  end
end

---@param client uv_tcp_t
---@param req table
local function handle_open(client, req)
  local ok, payload = pcall(vim.json.decode, req.body or "")
  if not ok or type(payload) ~= "table" then
    respond(client, "400 Bad Request", "text/plain", "Invalid JSON")
    return
  end

  local success, err = M.open_note_by_id(payload.id, payload.open)
  if not success then
    respond(client, "404 Not Found", "text/plain", err or "Not found")
    return
  end

  respond(client, "200 OK", "application/json", vim.json.encode { ok = true })
end

---@param client uv_tcp_t
---@param request string
local function handle_request(client, request)
  local req = parse_request(request)

  if req.path == "/api/graph" and req.method == "GET" then
    local ok, body = pcall(function()
      return vim.json.encode(M.build_graph())
    end)
    if ok then
      respond(client, "200 OK", "application/json", body)
    else
      respond(client, "500 Internal Server Error", "text/plain", tostring(body))
    end
  elseif (req.path == "/" or req.path == "/index.html" or req.path == "/local") and req.method == "GET" then
    respond(client, "200 OK", "text/html; charset=utf-8", graph_page())
  elseif req.path == "/events" and req.method == "GET" then
    if req.params.token ~= M._token then
      respond(client, "403 Forbidden", "text/plain", "Forbidden")
    else
      respond_events(client)
    end
  elseif req.path == "/api/open" and req.method == "POST" then
    if req.params.token ~= M._token then
      respond(client, "403 Forbidden", "text/plain", "Forbidden")
    else
      handle_open(client, req)
    end
  elseif req.method ~= "GET" and req.method ~= "POST" then
    respond(client, "405 Method Not Allowed", "text/plain", "Method not allowed")
  else
    respond(client, "404 Not Found", "text/plain", "Not found")
  end
end

--- Start the graph HTTP server on the given port.
---@param port integer
---@return boolean success
function M.start_server(port)
  local server = uv.new_tcp()
  if not server then
    return false
  end

  local ok = server:bind("127.0.0.1", port)
  if not ok then
    server:close()
    return false
  end

  ok = server:listen(128, function(err)
    if err then
      vim.notify("Graph server error: " .. tostring(err), vim.log.levels.ERROR)
      return
    end

    local client = uv.new_tcp()
    if not client then
      return
    end

    server:accept(client)

    local chunks = {}
    client:read_start(function(read_err, data)
      if read_err then
        client:close()
        return
      end
      if not data then
        return
      end

      chunks[#chunks + 1] = data
      local request = table.concat(chunks)
      if request_complete(request) then
        client:read_stop()
        handle_request(client, request)
      end
    end)
  end)

  if not ok then
    server:close()
    return false
  end

  -- Do not keep headless Neovim alive just because the graph server is open.
  server:unref()

  M._server = server
  M._port = port
  M._token = make_token()
  M._sse_clients = {}
  ensure_live_hooks()
  return true
end

--- Stop the graph server.
function M.stop_server()
  if M._server then
    M._server:close()
    M._server = nil
    M._port = nil
    M._token = nil
  end

  if M._sse_clients then
    for client in pairs(M._sse_clients) do
      close_client(client)
    end
    M._sse_clients = nil
  end

  if M._graph_update_timer then
    M._graph_update_timer:stop()
    M._graph_update_timer:close()
    M._graph_update_timer = nil
  end

  if M._unregister_watchfiles then
    M._unregister_watchfiles()
    M._unregister_watchfiles = nil
  end

  if M._augroup then
    pcall(vim.api.nvim_del_augroup_by_id, M._augroup)
    M._augroup = nil
  end
  M._live_hooks_started = nil
end

---@param path string
---@return boolean
local function open_url(path)
  if M._server then
    local url = "http://127.0.0.1:" .. M._port .. path
    vim.notify("Graph view already running on " .. url)
    vim.ui.open(url)
    return true
  end

  for port = 49876, 49885 do
    if M.start_server(port) then
      local url = "http://127.0.0.1:" .. port .. path
      vim.notify("Graph view at " .. url)
      vim.ui.open(url)
      return true
    end
  end

  vim.notify("Failed to start graph server (ports 49876-49885 busy)", vim.log.levels.ERROR)
  return false
end

--- Main entry point: start the server and open the global graph.
function M.open_graph()
  open_url "/"
end

--- Main entry point: start the server and open a local graph for the current note.
function M.open_graph_local()
  local note_id = M.current_note_id()
  if not note_id then
    vim.notify("Current buffer is not a markdown note in the vault", vim.log.levels.ERROR)
    return
  end

  open_url("/local?note=" .. vim.uri_encode(note_id))
end

return M
