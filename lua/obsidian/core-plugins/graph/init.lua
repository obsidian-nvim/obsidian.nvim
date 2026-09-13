--- Minimal local graph view for obsidian.nvim.
---
--- Builds the note graph from the cache and serves a small browser UI from a
--- local HTTP server.

local Path = require "obsidian.path"
local Graph = require "obsidian.graph"
local HttpServer = require "obsidian.web.server"
local watchfiles = require "obsidian.lsp.watchfiles"
local cache = require "obsidian.cache"
local actions = require "obsidian.core-plugins.graph.actions"

local uv = vim.uv

local M = {}

---Register a whole-note context menu action. See graph/actions.lua for the contract.
M.register_action = actions.register

---@type obsidian.web.Server?
M._server = nil
---@type table?
M._graph_cache = nil
---@type table<string, obsidian.graph.Node>?
M._graph_by_id = nil
---@type string?
M._graph_cache_dir = nil

local SSE_HEARTBEAT_MS = 25000
local MARKDOWN_EXTENSIONS = { md = true, markdown = true, qmd = true, base = true }

local function strip_markdown_suffix(path)
  local ext = (path:match "%.([^./]+)$" or ""):lower()
  if MARKDOWN_EXTENSIONS[ext] then
    return path:sub(1, #path - #ext - 1)
  end
  return path
end

---@param rel string
---@return string
local function note_id_from_relative_path(rel)
  return strip_markdown_suffix(rel:gsub("\\", "/"))
end

---@return string|?
local function current_note_id()
  local ok, rel = pcall(function()
    return Path.buffer(0):vault_relative_path { strict = true }
  end)
  if not ok or not rel then
    return nil
  end

  local id = note_id_from_relative_path(tostring(rel))
  if id == tostring(rel) then
    return nil
  end
  return id
end

M.current_note_id = current_note_id

---@param target string
---@return string?
local function target_extension(target)
  return (target:match "%.([^./]+)$" or ""):lower():match "^(.+)$"
end

---Build graph data from the current cache snapshot.
---@return obsidian.graph.Table
function M.build_graph()
  return Graph.from_cache():to_table { include_tag_nodes = true }
end

function M.invalidate_graph_cache()
  M._graph_cache = nil
  M._graph_by_id = nil
  M._graph_cache_dir = nil
end

---@param force boolean?
---@return table graph
local function get_graph(force)
  local vault_dir = tostring(Obsidian.dir)
  if force or not M._graph_cache or M._graph_cache_dir ~= vault_dir then
    local graph = M.build_graph()
    local by_id = {}
    for _, node in ipairs(graph.nodes or {}) do
      by_id[node.id] = node
    end
    M._graph_cache = graph
    M._graph_by_id = by_id
    M._graph_cache_dir = vault_dir
  end

  ---@diagnostic disable-next-line: return-type-mismatch
  return M._graph_cache
end

---@param id string
---@return obsidian.graph.Node?
local function node_by_id(id)
  get_graph(false)
  local node = M._graph_by_id and M._graph_by_id[id] or nil
  if not node then
    get_graph(true)
    node = M._graph_by_id and M._graph_by_id[id] or nil
  end
  return node
end

---@return string
local function make_token()
  return vim.fn.sha256(tostring(uv.hrtime()) .. tostring(math.random()) .. tostring {})
end

---@param client any
local function close_client(client)
  HttpServer.close_client(client)
end

---@param client any
local function remove_sse_client(client)
  if M._sse_clients then
    M._sse_clients[client] = nil
  end
  close_client(client)
end

local function stop_sse_heartbeat()
  if M._sse_heartbeat_timer then
    M._sse_heartbeat_timer:stop()
    M._sse_heartbeat_timer:close()
    M._sse_heartbeat_timer = nil
  end
end

local function start_sse_heartbeat()
  if M._sse_heartbeat_timer or not uv.new_timer then
    return
  end

  local timer = uv.new_timer()
  if not timer then
    return
  end
  timer:unref()
  timer:start(SSE_HEARTBEAT_MS, SSE_HEARTBEAT_MS, function()
    vim.schedule(function()
      if not M._sse_clients or not next(M._sse_clients) then
        stop_sse_heartbeat()
        return
      end

      for client in pairs(M._sse_clients) do
        if client:is_closing() then
          M._sse_clients[client] = nil
        else
          client:write(": ping\n\n", function(err)
            if err then
              remove_sse_client(client)
            end
          end)
        end
      end
    end)
  end)
  M._sse_heartbeat_timer = timer
end

--- Serve a single HTTP response.
---@param client any
---@param status string e.g. "200 OK"
---@param content_type string
---@param body string
local function respond(client, status, content_type, body)
  HttpServer.respond(client, status, content_type, body)
end

---@return string
local function graph_page()
  return require("obsidian.core-plugins.graph.web").render { token = M._token or "" }
end

---@param id string
---@return string|?
function M.note_path_by_id(id)
  if type(id) ~= "string" or id == "" then
    return nil
  end

  local node = node_by_id(id)
  return node and node.path or nil
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

  local function open_note()
    require("obsidian.api").open_note({ filename = path }, cmd)
  end
  if vim.in_fast_event() then
    vim.schedule(open_note)
    return true
  end

  -- Menu actions already run on the main loop; report opening failures to the browser.
  local ok, err = pcall(open_note)
  return ok, not ok and tostring(err) or nil
end

---@param client any
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
      remove_sse_client(client)
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

  local ok, graph = pcall(get_graph, true)
  if ok then
    M.broadcast { type = "graph:update", graph = graph, reason = reason }
  end
end

---@param reason string?
function M.schedule_graph_update(reason)
  M.invalidate_graph_cache()
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
  local id = current_note_id()
  if not id then
    return
  end

  M.broadcast { type = "active:set", id = id }
  M.broadcast { type = "local:set_root", id = id }
end

---@param events any[]
function M.handle_watchfiles(events)
  if not M._server then
    return
  end

  local FileChangeType = vim.lsp.protocol.FileChangeType
  for _, event in ipairs(events) do
    local type = event.type
    if
      type == FileChangeType.Created
      or type == FileChangeType.Changed
      or type == FileChangeType.Deleted
      or type == "created"
      or type == "changed"
      or type == "deleted"
      or type == "renamed"
    then
      M.schedule_graph_update "files"
      return
    end
  end
end

local function ensure_live_hooks()
  if M._live_hooks_started then
    return
  end

  M._sse_clients = M._sse_clients or {}
  M._watchfiles_unregister = watchfiles.register_handler(function(events)
    M.handle_watchfiles(events)
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

---@param client any
local function respond_events(client)
  local header = table.concat({
    "HTTP/1.1 200 OK",
    "Content-Type: text/event-stream",
    "Cache-Control: no-cache",
    "Connection: keep-alive",
    "",
    "",
  }, "\r\n")

  M._sse_clients = M._sse_clients or {}
  M._sse_clients[client] = true
  client:write(header)
  client:unref()
  start_sse_heartbeat()

  send_sse(client, { type = "graph:update", graph = get_graph(false), reason = "connect" })
  local id = current_note_id()
  if id then
    send_sse(client, { type = "active:set", id = id })
    send_sse(client, { type = "local:set_root", id = id })
  end
end

---@param client any
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

---@param id string
---@return obsidian.graph.ActionContext?
local function action_context(id)
  local node = node_by_id(id)
  if not node or node.type ~= "note" or not node.exists or not node.path then
    return nil
  end
  -- The cache may still contain a note deleted since the menu was opened.
  local stat = uv.fs_stat(node.path)
  if not stat or stat.type ~= "file" then
    return nil
  end
  return { node = vim.deepcopy(node), path = node.path }
end

---@param client any
---@param req obsidian.web.Request
local function handle_actions(client, req)
  if not M._token or req.params.token ~= M._token then
    respond(client, "403 Forbidden", "text/plain", "Forbidden")
    return
  end

  local id, name = req.params.id, nil
  if req.method == "POST" then
    local ok, payload = pcall(vim.json.decode, req.body)
    if not ok or type(payload) ~= "table" or type(payload.name) ~= "string" or payload.name == "" then
      respond(client, "400 Bad Request", "text/plain", "Expected JSON with id and name")
      return
    end
    id, name = payload.id, payload.name
  end
  if type(id) ~= "string" or id == "" then
    respond(client, "400 Bad Request", "text/plain", "Expected a note id")
    return
  end

  -- Conditions, titles and callbacks may use Neovim APIs, unlike the libuv handler.
  vim.schedule(function()
    if client:is_closing() then
      return
    end
    if req.params.token ~= M._token then
      respond(client, "403 Forbidden", "text/plain", "Forbidden")
      return
    end
    ---@return string status
    ---@return string body
    local function action_response()
      local ctx = action_context(id)
      if not ctx then
        if req.method == "GET" then
          return "200 OK", "[]"
        end
        return "404 Not Found", "Note not found"
      end
      if name then
        local success, err = actions.execute(name, ctx)
        if not success then
          return "404 Not Found", err or "Action unavailable"
        end
        return "200 OK", vim.json.encode { ok = true }
      end
      return "200 OK", vim.json.encode(actions.list(ctx))
    end
    local ok, status, body = pcall(action_response)
    if not ok then
      respond(client, "500 Internal Server Error", "text/plain", tostring(status))
    else
      respond(client, status, status == "200 OK" and "application/json" or "text/plain", body)
    end
  end)
end

---@param client any
---@param req obsidian.web.Request
local function handle_request(client, req)
  if req.path == "/api/graph" and req.method == "GET" then
    if req.params.token ~= M._token then
      respond(client, "403 Forbidden", "text/plain", "Forbidden")
      return
    end

    local ok, body = pcall(function()
      return vim.json.encode(get_graph(false))
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
  elseif
    (req.path == "/api/actions" and req.method == "GET") or (req.path == "/api/action" and req.method == "POST")
  then
    handle_actions(client, req)
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
  local server = HttpServer.new {
    port = port,
    on_error = function(err)
      vim.notify("Graph server error: " .. tostring(err), vim.log.levels.ERROR)
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
  M._sse_clients = {}
  M.invalidate_graph_cache()
  ensure_live_hooks()
  if cache.is_enabled() and not cache.is_ready() then
    cache.when_ready(function()
      M.schedule_graph_update "cache"
    end)
  end
  return true
end

--- Stop the graph server.
function M.stop_server()
  if M._server then
    M._server:stop()
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

  stop_sse_heartbeat()
  M.invalidate_graph_cache()

  if M._augroup then
    pcall(vim.api.nvim_del_augroup_by_id, M._augroup)
    M._augroup = nil
  end
  if M._watchfiles_unregister then
    M._watchfiles_unregister()
    M._watchfiles_unregister = nil
  end
  M._live_hooks_started = nil
end

---@param arg string?
---@return { kind: "note", id: string }|{ kind: "folder", folder: string }|nil scope
---@return string? err
local function resolve_graph_arg(arg)
  local trimmed = vim.trim(arg or "")
  if trimmed == "" then
    return nil, nil
  end

  local expanded = tostring(vim.fn.expand(trimmed))
  local target_arg = expanded ~= "" and expanded or trimmed

  local raw_path = Path.new(target_arg)
  local candidates
  if raw_path:is_absolute() then
    candidates = { raw_path }
  else
    candidates = { Path.new(vim.fs.joinpath(tostring(Obsidian.dir), target_arg)), raw_path }
  end

  local root = Obsidian.dir:resolve { strict = true }
  for _, candidate in ipairs(candidates) do
    local ok, resolved = pcall(function()
      return candidate:resolve { strict = true }
    end)
    if ok then
      local rel
      if tostring(resolved) == tostring(root) then
        rel = ""
      else
        local rel_ok, rel_path = pcall(function()
          return resolved:relative_to(root)
        end)
        if rel_ok then
          rel = tostring(rel_path):gsub("\\", "/")
        end
      end

      if rel then
        if resolved:is_dir() then
          rel = rel:gsub("/+$", "")
          if rel == "" then
            return nil, nil
          end
          return { kind = "folder", folder = rel }, nil
        elseif resolved:is_file() then
          local ext = target_extension(rel)
          if not (ext and MARKDOWN_EXTENSIONS[ext]) then
            return nil, "Graph target must be a markdown file or vault folder"
          end
          return { kind = "note", id = note_id_from_relative_path(rel) }, nil
        end
      end
    end
  end

  return nil, "Graph target not found in vault: " .. trimmed
end

M.resolve_graph_arg = resolve_graph_arg

---@param path string
---@return boolean
local function open_url(path)
  if M._server then
    local url = M._server:url(path)
    vim.notify("Graph view already running on " .. url)
    vim.ui.open(url)
    return true
  end

  for port = 49876, 49885 do
    if M.start_server(port) then
      ---@cast M._server obsidian.web.Server
      local url = M._server:url(path)
      vim.notify("Graph view at " .. url)
      vim.ui.open(url)
      return true
    end
  end

  vim.notify("Failed to start graph server (ports 49876-49885 busy)", vim.log.levels.ERROR)
  return false
end

--- Main entry point: start the server and open the graph.
---@param target string?
function M.open_graph(target)
  if not cache.is_enabled() then
    vim.notify("Graph view requires cache.enabled = true", vim.log.levels.ERROR)
    return
  elseif not cache.is_ready() then
    cache.when_ready(function()
      M.open_graph(target)
    end)
    return
  end

  local scope, err = resolve_graph_arg(target)
  if err then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  if not scope then
    open_url "/"
  elseif scope.kind == "note" then
    open_url("/local?note=" .. vim.uri_encode(scope.id))
  elseif scope.kind == "folder" then
    open_url("/local?folder=" .. vim.uri_encode(scope.folder))
  end
end

return M
