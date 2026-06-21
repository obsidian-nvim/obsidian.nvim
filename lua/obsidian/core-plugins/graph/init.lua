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
    client:shutdown(function()
      client:close()
    end)
  end)
end

---@param client uv_tcp_t
---@param request string
local function handle_request(client, request)
  local method, path = request:match "^(%S+)%s+(%S+)"
  path = path and path:gsub("%?.*$", "")

  if method ~= "GET" then
    respond(client, "405 Method Not Allowed", "text/plain", "Method not allowed")
  elseif path == "/api/graph" then
    local ok, body = pcall(function()
      return vim.json.encode(M.build_graph())
    end)
    if ok then
      respond(client, "200 OK", "application/json", body)
    else
      respond(client, "500 Internal Server Error", "text/plain", tostring(body))
    end
  elseif path == "/" or path == "/index.html" or path == "/local" then
    respond(client, "200 OK", "text/html; charset=utf-8", require "obsidian.core-plugins.graph.web")
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
      if request:find("\r\n\r\n", 1, true) or request:find("\n\n", 1, true) then
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
  return true
end

--- Stop the graph server.
function M.stop_server()
  if M._server then
    M._server:close()
    M._server = nil
    M._port = nil
  end
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
