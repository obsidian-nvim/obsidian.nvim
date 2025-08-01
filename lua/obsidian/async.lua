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

return M
