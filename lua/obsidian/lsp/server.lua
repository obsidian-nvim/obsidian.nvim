local handlers = require "obsidian.lsp.handlers"
local log = require "obsidian.log"

return function(dispatchers)
  local server = {}
  local closing = false

  local message_id = 0

  --- Handlers receive (params, callback) and invoke callback(err, result).
  ---@param method string
  ---@param params table?
  ---@param callback fun(err: lsp.ResponseError?, result: any)
  ---@param notify_reply_callback fun(message_id: integer)?
  ---@return boolean success
  ---@return integer? id
  server.request = function(method, params, callback, notify_reply_callback)
    message_id = message_id + 1
    local id = message_id

    --- Deliver response and bookkeeping on the main thread exactly once.
    local responded = false
    local function deliver(err, result)
      if responded then
        return
      end
      responded = true
      vim.schedule(function()
        callback(err, result)
        if notify_reply_callback then
          notify_reply_callback(id)
        end
      end)
    end

    local handler = handlers[method]
    if not handler then
      deliver({ code = -32601, message = "method not found: " .. method }, nil)
      return true, id
    end

    local ok, call_err = pcall(handler, params, deliver, dispatchers)
    if not ok then
      deliver({ code = -32603, message = "internal error: " .. tostring(call_err) }, nil)
    end

    return true, id
  end

  server.notify = function(method, ...)
    local handler = handlers[method]
    if not handler then
      -- Return true (server is active) so Neovim fires LspNotify for
      -- notifications like textDocument/didChange which trigger fold refresh.
      return true
    end

    local ok, err = pcall(handler, ..., dispatchers)
    if not ok then
      log.err("[obsidian-ls] notify handler error (" .. method .. "): " .. tostring(err))
    end
    return ok
  end

  server.is_closing = function()
    return closing
  end

  server.terminate = function()
    closing = true
  end

  return server
end
