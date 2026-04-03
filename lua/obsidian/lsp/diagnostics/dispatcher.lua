local dead_links_analysis = require "obsidian.analysis.dead_links"

---@class obsidian.lsp.DiagnosticsHandler
---@field id string
---@field analyze fun(uri: string, text: string|?): lsp.Diagnostic[]
---@field invalidate_cache fun(): nil

---@class obsidian.lsp.DiagnosticsDispatcher
---@field timers table<string, uv_timer_t>
---@field interval_getter fun(): integer
---@field handlers table<string, obsidian.lsp.DiagnosticsHandler>
local Dispatcher = {}
Dispatcher.__index = Dispatcher

local DEFAULT_INTERVAL_MS = 250

---@return integer
local function default_interval_getter()
  local v = tonumber(vim.g.diagnostic_interval)
  if v and v > 0 then
    return math.floor(v)
  end
  return DEFAULT_INTERVAL_MS
end

---@param entries obsidian.analysis.DeadLinkEntry[]
---@return lsp.Diagnostic[]
local function dead_links_to_diagnostics(entries)
  ---@type lsp.Diagnostic[]
  local diagnostics = {}

  for _, entry in ipairs(entries) do
    diagnostics[#diagnostics + 1] = {
      range = {
        start = { line = entry.line - 1, character = entry.start },
        ["end"] = { line = entry.line - 1, character = entry.end_col },
      },
      severity = vim.lsp.protocol.DiagnosticSeverity.Warning,
      source = "obsidian-ls",
      code = "dead-link",
      message = "Unresolved internal link",
    }
  end

  return diagnostics
end

---@param uri string
---@param text string|?
---@return lsp.Diagnostic[]
local function analyze_dead_links(uri, text)
  local entries = dead_links_analysis.collect {
    source_path = vim.uri_to_fname(uri),
    text = text,
    use_cache = true,
  }
  return dead_links_to_diagnostics(entries)
end

---@return table<string, obsidian.lsp.DiagnosticsHandler>
local function default_handlers()
  return {
    dead_links = {
      id = "dead_links",
      analyze = analyze_dead_links,
      invalidate_cache = dead_links_analysis.invalidate_cache,
    },
  }
end

---@param opts? { interval_getter: fun(): integer|?, handlers: table<string, obsidian.lsp.DiagnosticsHandler>|? }
---@return obsidian.lsp.DiagnosticsDispatcher
Dispatcher.new = function(opts)
  opts = opts or {}
  local self = {
    timers = {},
    interval_getter = opts.interval_getter or default_interval_getter,
    handlers = opts.handlers or default_handlers(),
  }
  return setmetatable(self, Dispatcher)
end

---@param uri string
function Dispatcher:cancel(uri)
  local timer = self.timers[uri]
  if timer == nil then
    return
  end

  timer:stop()
  timer:close()
  self.timers[uri] = nil
end

---@param dispatchers table
---@param uri string
---@param diagnostics lsp.Diagnostic[]
function Dispatcher:publish(dispatchers, uri, diagnostics)
  dispatchers.notification("textDocument/publishDiagnostics", {
    uri = uri,
    diagnostics = diagnostics,
  })
end

---@param dispatchers table
---@param uri string
---@param text string|?
function Dispatcher:run(dispatchers, uri, text)
  ---@type lsp.Diagnostic[]
  local diagnostics = {}

  for _, handler in pairs(self.handlers) do
    local handler_diagnostics = handler.analyze(uri, text)
    if handler_diagnostics and #handler_diagnostics > 0 then
      vim.list_extend(diagnostics, handler_diagnostics)
    end
  end

  self:publish(dispatchers, uri, diagnostics)
end

---@param dispatchers table
---@param uri string
---@param text string|?
---@param delay_ms integer|?
function Dispatcher:schedule(dispatchers, uri, text, delay_ms)
  self:cancel(uri)

  local timer = vim.uv.new_timer()
  if timer == nil then
    self:run(dispatchers, uri, text)
    return
  end

  self.timers[uri] = timer
  timer:start(
    delay_ms or self.interval_getter(),
    0,
    vim.schedule_wrap(function()
      self:cancel(uri)
      self:run(dispatchers, uri, text)
    end)
  )
end

---@param dispatchers table
---@param uri string
function Dispatcher:clear(dispatchers, uri)
  self:cancel(uri)
  self:publish(dispatchers, uri, {})
end

function Dispatcher:invalidate_cache()
  for _, handler in pairs(self.handlers) do
    if handler.invalidate_cache then
      handler.invalidate_cache()
    end
  end
end

return Dispatcher.new()
