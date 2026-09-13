local helpers = require "tests.helpers"

local T, child = helpers.child_vault {
  pre_case = [=[
local cache = require "obsidian.cache"
vim.fn.writefile({ "---", "tags: [graph]", "---", "[[Missing]]" }, tostring(Obsidian.dir / "A.md"))
vim.fn.writefile({ "# B" }, tostring(Obsidian.dir / "B.md"))
cache.setup { enabled = true, backend = "memory" }
assert(vim.wait(3000, cache.is_ready), "cache not ready")
local graph = require "obsidian.core-plugins.graph"
assert(graph.start_server(0), "graph server failed")

-- Exercise the real transport: callbacks must leave the libuv fast event.
_G.graph_request = function(method, endpoint, payload, token)
  local client = assert(vim.uv.new_tcp())
  local body = type(payload) == "string" and payload or (payload and vim.json.encode(payload) or "")
  local sep = endpoint:find("?", 1, true) and "&" or "?"
  local url = endpoint .. sep .. "token=" .. (token or graph._token)
  local chunks, done, failure = {}, false, nil
  client:connect("127.0.0.1", graph._port, function(err)
    if err then
      failure, done = err, true
      client:close()
      return
    end
    client:read_start(function(read_err, data)
      if read_err or not data then
        failure, done = read_err, true
        client:close()
      else
        chunks[#chunks + 1] = data
      end
    end)
    client:write(method .. " " .. url .. " HTTP/1.1\r\nHost: localhost\r\nContent-Length: " .. #body .. "\r\n\r\n" .. body)
  end)
  assert(vim.wait(3000, function() return done end), "graph HTTP response timed out")
  assert(not failure, failure)
  local response = table.concat(chunks)
  local status = tonumber(response:match "^HTTP/1.1 (%d+)")
  return status, response:match "\r\n\r\n(.*)$"
end
]=],
}

local function run(code)
  child.lua([[
local graph = require "obsidian.core-plugins.graph"
local request = _G.graph_request
local eq = MiniTest.expect.equality
]] .. code)
end

T["built-ins and non-note nodes"] = function()
  run [[
local status, body = request("GET", "/api/actions?id=A")
eq(200, status)
eq({
  { name = "open", title = "Open" },
  { name = "copy_path", title = "Copy path" },
}, vim.json.decode(body))
for _, id in ipairs { "tag:graph", "missing:Missing", "unknown" } do
  status, body = request("GET", "/api/actions?id=" .. vim.uri_encode(id))
  eq({ 200, "[]" }, { status, body })
  eq(404, (request("POST", "/api/action", { id = id, name = "open" })))
end
]]
end

T["registry order, validation, unregister and server restart"] = function()
  run [[
local opts = { name = "custom", title = "Custom", fn = function() end }
local unregister = graph.register_action(opts)
graph.register_action { name = "last", title = "Last", fn = function() end }
eq(false, (pcall(graph.register_action, opts)))
eq(false, (pcall(graph.register_action, { name = "", title = "", fn = function() end })))
eq(false, (pcall(graph.register_action, { name = "invalid", title = "Invalid" })))
graph.stop_server()
eq(true, graph.start_server(0))
local _, body = request("GET", "/api/actions?id=A")
local listed = vim.json.decode(body)
eq("custom", listed[3].name)
eq("last", listed[4].name)
unregister()
unregister()
-- An old unregister closure must not remove a new registration with the same name.
graph.register_action(opts)
unregister()
_, body = request("GET", "/api/actions?id=A")
listed = vim.json.decode(body)
eq("last", listed[3].name)
eq("custom", listed[4].name)
]]
end

T["callbacks target the clicked note on the main loop"] = function()
  run [[
vim.cmd.edit(tostring(Obsidian.dir / "B.md"))
local target, enabled = nil, true
graph.register_action {
  name = "custom",
  title = function(ctx)
    assert(not vim.in_fast_event(), "title in fast event")
    return "Custom " .. ctx.node.id
  end,
  cond = function(ctx)
    assert(not vim.in_fast_event(), "condition in fast event")
    assert(ctx.path == tostring(Obsidian.dir / "A.md"), "wrong note")
    return enabled
  end,
  fn = function(ctx)
    assert(not vim.in_fast_event(), "callback in fast event")
    target = ctx.path
  end,
}
local status, body = request("GET", "/api/actions?id=A")
eq(200, status)
eq({ name = "custom", title = "Custom A" }, vim.json.decode(body)[3])
status = request("POST", "/api/action", { id = "A", name = "custom", path = "/untrusted/path" })
eq(200, status)
eq(tostring(Obsidian.dir / "A.md"), target)
eq(tostring(Obsidian.dir / "B.md"), vim.api.nvim_buf_get_name(0))
enabled, target = false, nil
status, body = request("POST", "/api/action", { id = "A", name = "custom" })
eq({ 404, "Action unavailable" }, { status, body })
eq(nil, target)
_, body = request("GET", "/api/actions?id=A")
eq(2, #vim.json.decode(body))
]]
end

T["open and copy path"] = function()
  run [[
vim.cmd.edit(tostring(Obsidian.dir / "B.md"))
local copied
local original_has = vim.fn.has
vim.fn.has = function(feature)
  return feature == "clipboard" and 1 or original_has(feature)
end
vim.fn.setreg = function(...)
  copied = { ... }
  return 0
end
local status = request("POST", "/api/action", { id = "A", name = "copy_path" })
eq(200, status)
eq({ "+", tostring(Obsidian.dir / "A.md"), "v" }, copied)
eq(tostring(Obsidian.dir / "B.md"), vim.api.nvim_buf_get_name(0))
status = request("POST", "/api/action", { id = "A", name = "open" })
eq(200, status)
eq(tostring(Obsidian.dir / "A.md"), vim.api.nvim_buf_get_name(0))
]]
end

T["authentication and malformed requests"] = function()
  run [[
eq(403, (request("GET", "/api/actions?id=A", nil, "invalid")))
eq(403, (request("POST", "/api/action", { id = "A", name = "open" }, "invalid")))
eq(400, (request("GET", "/api/actions")))
for _, payload in ipairs { "not json", "[]", "null", "1", {}, { id = {}, name = "open" }, { id = "A", name = 1 } } do
  eq(400, (request("POST", "/api/action", payload)))
end
eq(404, (request("POST", "/api/action", { id = "A", name = "unknown" })))
]]
end

T["deleted notes cannot execute stale actions"] = function()
  run [[
request("GET", "/api/actions?id=A")
vim.fn.delete(tostring(Obsidian.dir / "A.md"))
eq(404, (request("POST", "/api/action", { id = "A", name = "open" })))
local status, body = request("GET", "/api/actions?id=A")
eq({ 200, "[]" }, { status, body })
]]
end

T["callback and built-in failures are returned"] = function()
  run [[
graph.register_action {
  name = "broken",
  title = "Broken",
  fn = function() error "callback failed" end,
}
local status, body = request("POST", "/api/action", { id = "A", name = "broken" })
eq(500, status)
eq(true, body:find("callback failed", 1, true) ~= nil)
local unregister = graph.register_action {
  name = "bad_condition",
  title = "Broken",
  cond = function() error "condition failed" end,
  fn = function() end,
}
eq(500, (request("GET", "/api/actions?id=A")))
eq(500, (request("POST", "/api/action", { id = "A", name = "bad_condition" })))
unregister()
graph.register_action {
  name = "bad_title",
  title = function() error "title failed" end,
  fn = function() end,
}
eq(500, (request("GET", "/api/actions?id=A")))
local original_has = vim.fn.has
vim.fn.has = function(feature)
  return feature == "clipboard" and 0 or original_has(feature)
end
eq(500, (request("POST", "/api/action", { id = "A", name = "copy_path" })))
require("obsidian.api").open_note = function() error "open failed" end
eq(500, (request("POST", "/api/action", { id = "A", name = "open" })))
]]
end

return T
