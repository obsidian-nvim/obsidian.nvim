local volatile = require "obsidian.cache.volatile"
local eq = MiniTest.expect.equality
local T = MiniTest.new_set()

T["vault index builds lazily and coalesces waiters"] = function()
  local builds = 0
  local finish
  local index = volatile.vault_index {
    build = function(_, done)
      builds = builds + 1
      finish = done
    end,
  }
  local values = {}
  index:get("vault", {}, function(value)
    values[#values + 1] = value
  end)
  index:get("vault", {}, function(value)
    values[#values + 1] = value
  end)
  eq(1, builds)
  eq({}, values)
  finish { ready = true }
  eq({ { ready = true }, { ready = true } }, values)
  eq({ ready = true }, index:peek "vault")
  index:dispose()
end

T["vault index rejects an invalidated asynchronous build"] = function()
  local finishes = {}
  local index = volatile.vault_index {
    build = function(_, done)
      finishes[#finishes + 1] = done
    end,
  }
  local result
  index:get("vault", {}, function(value)
    result = value
  end)
  index:invalidate "vault"
  eq(2, #finishes)
  finishes[1] "stale"
  eq(nil, result)
  finishes[2] "current"
  eq("current", result)
  index:dispose()
end

T["buffer values distinguish fresh, stale, and external epochs"] = function()
  local cache = volatile.buffer_values { max_entries_per_buffer = 2 }
  local buf = vim.api.nvim_create_buf(false, true)
  cache:set(buf, "range", { epoch = 1, revision = 1 }, { "hint" })
  eq({ "hint" }, cache:get(buf, "range", { epoch = 1, revision = 1 }))
  eq(nil, cache:get(buf, "range", { epoch = 1, revision = 2 }))
  eq({ "hint" }, cache:get(buf, "range", { epoch = 1, revision = 2 }, { allow_stale = true }))
  eq(nil, cache:get(buf, "range", { epoch = 2, revision = 1 }, { allow_stale = true }))
  vim.api.nvim_buf_delete(buf, { force = true })
end

return T
