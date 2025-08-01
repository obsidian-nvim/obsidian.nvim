local log = require "obsidian.log"
local util = require "obsidian.util"

local M = {}

---@param cmds string[]
---@param on_stdout function|? (string) -> nil
---@param on_exit function|? (integer) -> nil
---@param sync boolean
local init_job = function(cmds, on_stdout, on_exit, sync)
  local stderr_lines = false

  local on_obj = function(obj)
    --- NOTE: commands like `rg` return a non-zero exit code when there are no matches, which is okay.
    --- So we only log no-zero exit codes as errors when there's also stderr lines.
    if obj.code > 0 and stderr_lines then
      log.err("Command '%s' exited with non-zero code %s. See logs for stderr.", cmds, obj.code)
    elseif stderr_lines then
      log.warn("Captured stderr output while running command '%s'. See logs for details.", cmds)
    end
    if on_exit ~= nil then
      on_exit(obj.code)
    end
  end

  on_stdout = util.buffer_fn(on_stdout)

  local function stdout(err, data)
    if err ~= nil then
      return log.err("Error running command '%s'\n:%s", cmds, err)
    end
    if data ~= nil then
      on_stdout(data)
    end
  end

  local function stderr(err, data)
    if err then
      return log.err("Error running command '%s'\n:%s", cmds, err)
    elseif data ~= nil then
      if not stderr_lines then
        log.err("Captured stderr output while running command '%s'", cmds)
        stderr_lines = true
      end
      log.err("[stderr] %s", data)
    end
  end

  return function()
    log.debug("Initializing job '%s'", cmds)

    if sync then
      local obj = vim.system(cmds, { stdout = stdout, stderr = stderr }):wait()
      on_obj(obj)
      return obj
    else
      vim.system(cmds, { stdout = stdout, stderr = stderr }, on_obj)
    end
  end
end

---@param cmds string[]
---@param on_stdout function|? (string) -> nil
---@param on_exit function|? (integer) -> nil
---@return integer exit_code
M.run_job = function(cmds, on_stdout, on_exit)
  local job = init_job(cmds, on_stdout, on_exit, true)
  return job().code
end

---@param cmds string[]
---@param on_stdout function|? (string) -> nil
---@param on_exit function|? (integer) -> nil
M.run_job_async = function(cmds, on_stdout, on_exit)
  local job = init_job(cmds, on_stdout, on_exit, false)
  job()
end

---@param fn function
---@param timeout integer (milliseconds)
M.throttle = function(fn, timeout)
  ---@type integer
  local last_call = 0
  ---@type uv.uv_timer_t?
  local timer = nil

  return function(...)
    if timer ~= nil then
      timer:stop()
    end

    local ms_remaining = timeout - (vim.uv.now() - last_call)

    if ms_remaining > 0 then
      if timer == nil then
        timer = assert(vim.uv.new_timer())
      end

      local args = { ... }

      timer:start(
        ms_remaining,
        0,
        vim.schedule_wrap(function()
          if timer ~= nil then
            timer:stop()
            timer:close()
            timer = nil
          end

          last_call = vim.uv.now()
          fn(unpack(args))
        end)
      )
    else
      last_call = vim.uv.now()
      fn(...)
    end
  end
end

---Run an async function in a non-async context. The async function is expected to take a single
---callback parameters with the results. This function returns those results.
---@param async_fn_with_callback function (function,) -> any
---@param timeout integer|?
---@return ...any results
M.block_on = function(async_fn_with_callback, timeout)
  local done = false
  local result
  timeout = timeout and timeout or 2000

  local function collect_result(...)
    result = { ... }
    done = true
  end

  async_fn_with_callback(collect_result)

  vim.wait(timeout, function()
    return done
  end, 20, false)

  return unpack(result)
end

local max_timeout = 30000

--- @param thread thread
--- @param on_finish fun(err: string?, ...:any)
--- @param ... any
local function resume(thread, on_finish, ...)
  --- @type {n: integer, [1]:boolean, [2]:string|function}
  local ret = vim.F.pack_len(coroutine.resume(thread, ...))
  local stat = ret[1]

  if not stat then
    -- Coroutine had error
    on_finish(ret[2] --[[@as string]])
  elseif coroutine.status(thread) == "dead" then
    -- Coroutine finished
    on_finish(nil, unpack(ret, 2, ret.n))
  else
    local fn = ret[2]
    --- @cast fn -string

    --- @type boolean, string?
    local ok, err = pcall(fn, function(...)
      resume(thread, on_finish, ...)
    end)

    if not ok then
      on_finish(err)
    end
  end
end

--- @param func async fun(): ...:any
--- @param on_finish? fun(err: string?, ...:any)
function M.run(func, on_finish)
  local res --- @type {n:integer, [integer]:any}?
  resume(coroutine.create(func), function(err, ...)
    res = vim.F.pack_len(err, ...)
    if on_finish then
      on_finish(err, ...)
    end
  end)

  return {
    --- @param timeout? integer
    --- @return any ... return values of `func`
    wait = function(_self, timeout)
      vim.wait(timeout or max_timeout, function()
        return res ~= nil
      end)
      assert(res, "timeout")
      if res[1] then
        error(res[1])
      end
      return unpack(res, 2, res.n)
    end,
  }
end

--- Asynchronous blocking wait
--- @async
--- @param argc integer
--- @param fun function
--- @param ... any func arguments
--- @return any ...
function M.await(argc, fun, ...)
  assert(coroutine.running(), "Async.await() must be called from an async function")
  local args = vim.F.pack_len(...) --- @type {n:integer, [integer]:any}

  --- @param callback fun(...:any)
  return coroutine.yield(function(callback)
    args[argc] = assert(callback)
    fun(unpack(args, 1, math.max(argc, args.n)))
  end)
end

--- @async
--- @param max_jobs integer
--- @param funs (async fun())[]
function M.join(max_jobs, funs)
  if #funs == 0 then
    return
  end

  max_jobs = math.min(max_jobs, #funs)

  --- @type (async fun())[]
  local remaining = { select(max_jobs + 1, unpack(funs)) }
  local to_go = #funs

  M.await(1, function(on_finish)
    local function run_next()
      to_go = to_go - 1
      if to_go == 0 then
        on_finish()
      elseif #remaining > 0 then
        local next_fun = table.remove(remaining)
        M.run(next_fun, run_next)
      end
    end

    for i = 1, max_jobs do
      M.run(funs[i], run_next)
    end
  end)
end

return M
