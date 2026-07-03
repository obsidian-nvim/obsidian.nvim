--- Minimal local graph view for obsidian.nvim.
---
--- Builds the note graph from the cache when available and serves a small
--- browser UI from a local HTTP server.

local Path = require "obsidian.path"
local HttpServer = require "obsidian.web.server"
local watchfiles = require "obsidian.lsp.watchfiles"
local cache = require "obsidian.cache"
local cache_note = require "obsidian.cache.note"
local ignore = require "obsidian.ignore"

local uv = vim.uv

local M = {}

---@type obsidian.web.Server?
M._server = nil
---@type table?
M._graph_cache = nil
---@type table<string, table>?
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

---@param value any
---@return string[]
local function normalize_string_list(value)
  if type(value) ~= "table" then
    return {}
  end

  local out = {}
  for _, item in ipairs(value) do
    if type(item) == "string" and item ~= "" then
      out[#out + 1] = item
    end
  end
  return out
end

---@param target string
---@return string?
local function target_extension(target)
  return (target:match "%.([^./]+)$" or ""):lower():match "^(.+)$"
end

---@param target string
---@return "note"|"attachment"
local function target_kind(target)
  local ext = target_extension(target)
  if ext and not MARKDOWN_EXTENSIONS[ext] then
    return "attachment"
  else
    return "note"
  end
end

---@param target string
---@param kind "note"|"attachment"
---@return string[]
local function target_candidates(target, kind)
  if kind == "attachment" then
    return { target }
  end

  local ext = target_extension(target)
  if ext and MARKDOWN_EXTENSIONS[ext] then
    return { target }
  end

  return { target .. ".md", target .. ".markdown", target .. ".qmd", target .. ".base" }
end

---@param target string
---@param kind "note"|"attachment"
---@return boolean
local function target_is_ignored(target, kind)
  for _, candidate in ipairs(target_candidates(target, kind)) do
    if ignore.is_ignored(candidate) then
      return true
    end
  end
  return false
end

---@param target string
---@param kind "note"|"attachment"
---@return obsidian.Path|?
local function target_existing_path(target, kind)
  for _, candidate in ipairs(target_candidates(target, kind)) do
    local path = Path.new(vim.fs.joinpath(tostring(Obsidian.dir), candidate))
    if path:is_file() then
      return path
    end
  end
end

---@param id string
---@return string
local function node_folder(id)
  return id:match "^(.*)/[^/]+$" or ""
end

---@param id string
---@return string
local function node_title(id)
  return id:match "([^/]+)$" or id
end

---@param tag string
---@return string
local function tag_node_id(tag)
  return "tag:" .. tag
end

---@param nodes table[]
---@param node_set table<string, boolean>
---@param tag string
---@return string|?
local function ensure_tag_node(nodes, node_set, tag)
  if vim.startswith(tag, "#") then
    tag = tag:sub(2)
  end
  if tag == "" then
    return nil
  end

  local id = tag_node_id(tag)
  if node_set[id] then
    return id
  end

  nodes[#nodes + 1] = {
    id = id,
    title = "#" .. tag,
    folder = "",
    aliases = {},
    tags = {},
    type = "tag",
  }
  node_set[id] = true
  return id
end

---@param nodes table[]
---@param node_set table<string, boolean>
---@param target string
---@param kind "note"|"attachment"
---@return string|?
local function ensure_linked_node(nodes, node_set, target, kind)
  if target == "" or target_is_ignored(target, kind) then
    return nil
  end

  if node_set[target] then
    return target
  end

  local path = target_existing_path(target, kind)
  local exists = path ~= nil
  local node = {
    id = target,
    title = node_title(target),
    folder = node_folder(target),
    aliases = {},
    tags = {},
  }

  if path then
    node.path = tostring(path)
  end
  if not exists then
    node.exists = false
  end
  if kind == "attachment" then
    node.type = "attachment"
    node.exists = exists
  end

  nodes[#nodes + 1] = node
  node_set[target] = true
  return target
end

---@param rel string
---@return string
local function note_stem(rel)
  return vim.fn.fnamemodify(rel, ":t:r")
end

---@param row table
---@param fallback string
---@return string
local function row_title(row, fallback)
  if type(row.properties) == "table" and type(row.properties.title) == "string" then
    return row.properties.title
  end
  return fallback
end

---@return { path: string, rel: string, id: string, stem: string, row: table }[]
local function note_entries()
  local entries = {}
  local root = tostring(Obsidian.dir)

  local function add(abs, row)
    local rel = vim.fs.normalize(abs)
    local norm_root = vim.fs.normalize(root):gsub("/+$", "")
    if vim.startswith(rel, norm_root .. "/") then
      rel = rel:sub(#norm_root + 2)
    end
    rel = rel:gsub("\\", "/")
    entries[#entries + 1] = {
      path = abs,
      rel = rel,
      id = note_id_from_relative_path(rel),
      stem = note_stem(rel),
      row = row,
    }
  end

  if cache.is_enabled() and cache.is_ready() then
    for abs, row in pairs(cache.notes.all()) do
      if not ignore.is_ignored(abs) then
        add(abs, row)
      end
    end
  else
    local files = vim.fs.find(function(name, dir)
      local ext = (name:match "%.([^./]+)$" or ""):lower()
      if not MARKDOWN_EXTENSIONS[ext] then
        return false
      end
      return not ignore.is_ignored(dir .. "/" .. name)
    end, { type = "file", path = root, limit = math.huge })

    for _, abs in ipairs(files) do
      local row = cache_note.build(abs, root)
      if row then
        add(abs, row)
      end
    end
  end

  table.sort(entries, function(a, b)
    return a.rel < b.rel
  end)
  return entries
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
  local basename_id = basename and target_to_id[basename] or nil
  if basename_id then
    return basename_id
  end
end

--- Build graph data: note nodes and note-to-note links.
---@return table graph { nodes: {id:string, title:string, path:string|?, folder:string, aliases:string[], tags:string[], type:string|?, exists:boolean|?}[], links: {source:string, target:string}[] }
function M.build_graph()
  local entries = note_entries()
  local target_to_id = {}
  local nodes = {}
  local links = {}
  local link_set = {}
  local node_set = {}

  local function add_link(source, target)
    if not target or target == source then
      return
    end

    local key = source .. "\0" .. target
    if not link_set[key] then
      link_set[key] = true
      links[#links + 1] = { source = source, target = target }
    end
  end

  for _, entry in ipairs(entries) do
    local aliases = normalize_string_list(entry.row.aliases)
    local tags = normalize_string_list(entry.row.tags)
    local node = {
      id = entry.id,
      title = row_title(entry.row, entry.stem),
      path = entry.path,
      folder = node_folder(entry.id),
      aliases = aliases,
      tags = tags,
    }
    nodes[#nodes + 1] = node
    node_set[entry.id] = true
    target_to_id[entry.id] = entry.id

    if target_to_id[entry.stem] == nil then
      target_to_id[entry.stem] = entry.id
    elseif target_to_id[entry.stem] ~= entry.id then
      target_to_id[entry.stem] = false
    end

    for _, alias in ipairs(aliases) do
      if target_to_id[alias] == nil then
        target_to_id[alias] = entry.id
      elseif target_to_id[alias] ~= entry.id then
        target_to_id[alias] = false
      end
    end

    for _, tag in ipairs(tags) do
      add_link(entry.id, ensure_tag_node(nodes, node_set, tag))
    end
  end

  for _, entry in ipairs(entries) do
    for _, link in ipairs(entry.row.links_out or {}) do
      local target = normalize_target(link.target)
      if target then
        local resolved = resolve_target(target, target_to_id)
        local target_id = resolved or ensure_linked_node(nodes, node_set, target, target_kind(target))
        add_link(entry.id, target_id)
      end
    end
  end

  return { nodes = nodes, links = links }
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
---@return table|?
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

  vim.schedule(function()
    require("obsidian.api").open_note({ filename = path }, cmd)
  end)

  return true
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
