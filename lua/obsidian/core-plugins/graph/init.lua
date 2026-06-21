--- A minimal graph view for obsidian.nvim.
---
--- Finds all markdown notes in the vault, extracts wiki links,
--- and serves a force-directed graph via a local HTTP server.

local Path = require "obsidian.path"

local M = {}

--- Collect all .md notes in the vault recursively.
---@return obsidian.Path[]
function M.find_notes()
  local files = {}

  local function walk(dir)
    local h = vim.loop.fs_scandir(dir)
    if not h then
      return
    end
    while true do
      local name, type = vim.loop.fs_scandir_next(h)
      if not name then
        break
      end
      local full = Path.new(dir) / name
      if type == "directory" then
        if not vim.startswith(name, ".") and name ~= "node_modules" then
          walk(tostring(full))
        end
      elseif type == "file" and (name:match("%.md$") or name:match("%.markdown$")) then
        table.insert(files, full)
      end
    end
  end

  walk(tostring(Obsidian.dir))
  return files
end

--- Extract wiki link targets from a note.
--- Returns the stem of each [[target]] (without .md, alias, or fragment).
---@param path obsidian.Path
---@return string[]
function M.extract_links(path)
  local links = {}
  local f = io.open(tostring(path), "r")
  if not f then
    return links
  end

  for line in f:lines() do
    for target in line:gmatch("%[%[([^%[%]]+)%]%]") do
      local bare = target:match("^([^|]+)")
      if bare then
        local name = bare:match("^([^#]+)")
        if name then
          name = vim.trim(name)
          name = name:gsub("%.md$", "")
          table.insert(links, name)
        end
      end
    end
  end
  f:close()
  return links
end

--- Build graph data: nodes and edges.
---@return table { nodes: {id:string, title:string, path:string}[], links: {source:string, target:string}[] }
function M.build_graph()
  local files = M.find_notes()
  local node_map = {}
  local nodes = {}
  local edges = {}
  local edge_set = {}

  -- Compute vault-relative paths for all notes
  for _, filepath in ipairs(files) do
    local rel = filepath:vault_relative_path { strict = true }
    if rel then
      local name = tostring(rel):gsub("%.md$", "")
      local title = tostring(filepath.stem)
      node_map[name] = filepath
      table.insert(nodes, { id = name, title = title, path = tostring(filepath) })
    end
  end

  -- Extract links and build edges
  for _, filepath in ipairs(files) do
    local rel = filepath:vault_relative_path { strict = true }
    if rel then
      local source = tostring(rel):gsub("%.md$", "")
      local targets = M.extract_links(filepath)
      for _, target in ipairs(targets) do
        if node_map[target] then
          local edge_key = source .. "->" .. target
          if not edge_set[edge_key] then
            edge_set[edge_key] = true
            table.insert(edges, { source = source, target = target })
          end
        end
      end
    end
  end

  return { nodes = nodes, links = edges }
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
    client:shutdown()
    client:close()
  end)
end

--- Start the graph HTTP server on the given port.
---@param port integer
---@return boolean success
function M.start_server(port)
  local server = vim.loop.new_tcp()
  if not server then
    return false
  end

  local bind_ok, bind_err = pcall(function()
    server:bind("127.0.0.1", port)
  end)
  if not bind_ok then
    server:close()
    return false
  end

  local web_html = require("obsidian.core-plugins.graph.web")

  server:listen(128, function(err)
    if err then
      vim.notify("Graph server error: " .. tostring(err), vim.log.levels.ERROR)
      return
    end

    local client = vim.loop.new_tcp()
    server:accept(client)

    local chunks = {}
    client:read_start(function(err_chunk, data)
      if data then
        table.insert(chunks, data)
        local buf = table.concat(chunks)

        -- Check if we have the full request
        if buf:find("\r\n\r\n") or buf:find("\n\n") then
          -- Parse the request line
          local method, path = buf:match("^(%S+)%s+(%S+)")
          if method == "GET" then
            if path == "/api/graph" then
              local graph = M.build_graph()
              local json = vim.json.encode(graph)
              respond(client, "200 OK", "application/json", json)
            else
              respond(client, "200 OK", "text/html; charset=utf-8", web_html)
            end
          else
            respond(client, "405 Method Not Allowed", "text/plain", "Method not allowed")
          end
        end
      elseif err_chunk then
        client:close()
      end
    end)
  end)

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

--- Main entry point: start the server and open the browser.
function M.open_graph()
  if M._server then
    vim.notify("Graph view already running on http://127.0.0.1:" .. M._port)
    vim.ui.open("http://127.0.0.1:" .. M._port)
    return
  end

  -- Try ports 49876-49885
  for port = 49876, 49885 do
    if M.start_server(port) then
      vim.notify("Graph view at http://127.0.0.1:" .. port)
      vim.ui.open("http://127.0.0.1:" .. port)
      return
    end
  end

  vim.notify("Failed to start graph server (ports 49876-49885 busy)", vim.log.levels.ERROR)
end

return M
