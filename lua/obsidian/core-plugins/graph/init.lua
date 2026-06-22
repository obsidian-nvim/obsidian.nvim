--- Minimal local graph view for obsidian.nvim.
---
--- Scans markdown notes in the active vault, extracts internal links, and serves a
--- small browser UI from a local HTTP server.

local Frontmatter = require "obsidian.frontmatter"
local Path = require "obsidian.path"
local HttpServer = require "obsidian.web.server"
local refs = require "obsidian.parse.refs"
local parse_tags = require("obsidian.parse.tags").parse_tags
local api = require "obsidian.api"
local ignore = require "obsidian.ignore"

local uv = vim.uv

local M = {}

local SSE_HEARTBEAT_MS = 25000
local MARKDOWN_EXTENSIONS = { md = true, qmd = true, base = true }

local function strip_markdown_suffix(path)
  return path:gsub("%.md$", "")
end

---@return string|?
local function current_note_id()
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

-- TODO: use cache

--- Extract internal link targets from a note.
---@param path obsidian.Path
---@return string[]
local function extract_links(path)
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

  return { target .. ".md", target .. ".qmd", target .. ".base" }
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

---@param path obsidian.Path
---@return string[]
local function read_inline_tags(path)
  local f = io.open(tostring(path), "r")
  if not f then
    return {}
  end

  local tags = {}
  local seen = {}
  for line in f:lines() do
    for _, match in ipairs(parse_tags(line)) do
      local tag = line:sub(match[1] + 1, match[2])
      if tag ~= "" and not seen[tag] then
        tags[#tags + 1] = tag
        seen[tag] = true
      end
    end
  end
  f:close()
  return tags
end

---@param tags string[]
---@param extra string[]
---@return string[]
local function merge_tags(tags, extra)
  local out = {}
  local seen = {}
  for _, list in ipairs { tags, extra } do
    for _, tag in ipairs(list) do
      if not seen[tag] then
        out[#out + 1] = tag
        seen[tag] = true
      end
    end
  end
  return out
end

---@param path obsidian.Path
---@return string[] aliases
---@return string[] tags
---@return string? title
local function read_note_metadata(path)
  local inline_tags = read_inline_tags(path)
  local f = io.open(tostring(path), "r")
  if not f then
    return {}, inline_tags, nil
  end

  local first = f:read "*l"
  if not first or not first:match "^%-%-%-+$" then
    f:close()
    return {}, inline_tags, nil
  end

  local frontmatter_lines = {}
  for line in f:lines() do
    if line:match "^%-%-%-+$" then
      break
    end
    frontmatter_lines[#frontmatter_lines + 1] = line
  end
  f:close()

  local info, metadata = Frontmatter.parse(frontmatter_lines, path)
  local title = type(metadata.title) == "string" and metadata.title or nil
  return normalize_string_list(info.aliases), merge_tags(normalize_string_list(info.tags), inline_tags), title
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
---@return table graph { nodes: {id:string, title:string, path:string|?, folder:string, aliases:string[], tags:string[], type:string|?, exists:boolean|?}[], links: {source:string, target:string}[] }
function M.build_graph()
  -- TODO: use cache
  local files = api.dir(Obsidian.dir):map(Path.new):totable()
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

  for _, filepath in ipairs(files) do
    local rel = filepath:vault_relative_path { strict = true }
    local id = strip_markdown_suffix(tostring(rel))
    local stem = filepath.stem
    local aliases, tags, title = read_note_metadata(filepath)
    local node = {
      id = id,
      title = title or stem,
      path = tostring(filepath),
      folder = node_folder(id),
      aliases = aliases,
      tags = tags,
    }
    nodes[#nodes + 1] = node
    node_set[id] = true
    target_to_id[id] = id

    if target_to_id[stem] == nil then
      target_to_id[stem] = id
    elseif target_to_id[stem] ~= id then
      target_to_id[stem] = false
    end

    for _, alias in ipairs(aliases) do
      if target_to_id[alias] == nil then
        target_to_id[alias] = id
      elseif target_to_id[alias] ~= id then
        target_to_id[alias] = false
      end
    end

    for _, tag in ipairs(tags) do
      add_link(id, ensure_tag_node(nodes, node_set, tag))
    end
  end

  for _, filepath in ipairs(files) do
    local rel = filepath:vault_relative_path { strict = true }
    local source = strip_markdown_suffix(tostring(rel))

    for _, target in ipairs(extract_links(filepath)) do
      local resolved = resolve_target(target, target_to_id)
      local target_id = resolved or ensure_linked_node(nodes, node_set, target, target_kind(target))
      add_link(source, target_id)
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

---@param client uv_tcp_t
local function close_client(client)
  HttpServer.close_client(client)
end

---@param client uv_tcp_t
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
---@param client uv_tcp_t
---@param status string e.g. "200 OK"
---@param content_type string
---@param body string
local function respond(client, status, content_type, body)
  HttpServer.respond(client, status, content_type, body)
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

---@param events lsp.FileEvent[]
function M.handle_watchfiles(events)
  if not M._server then
    return
  end

  local FileChangeType = vim.lsp.protocol.FileChangeType
  for _, event in ipairs(events) do
    if event.type == FileChangeType.Created or event.type == FileChangeType.Deleted then
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
  M._live_hooks_started = nil
end

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
      local url = M._server:url(path)
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
  local note_id = current_note_id()
  if not note_id then
    vim.notify("Current buffer is not a markdown note in the vault", vim.log.levels.ERROR)
    return
  end

  open_url("/local?note=" .. vim.uri_encode(note_id))
end

return M
