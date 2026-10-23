local api = require "obsidian.api"
local log = require "obsidian.log"

local M = {}
local queues = {}

---Serialize operations that can change short-link resolution in one workspace.
---The task must call done after applying or verifying its edit.
---@param path string
---@param task fun(done: fun())
---@param opts { immediate: boolean? }?
function M.run(path, task, opts)
  local workspace = api.find_workspace(path)
  if not workspace then
    return task(function() end)
  end
  local root = tostring(workspace.root)
  local queue = queues[root] or { running = false, tasks = {} }
  queues[root] = queue
  queue.tasks[#queue.tasks + 1] = task

  local function next_task()
    local pending = table.remove(queue.tasks, 1)
    if not pending then
      queue.running = false
      return
    end
    queue.running = true
    local function execute()
      local finished = false
      local function done()
        if finished then
          return
        end
        finished = true
        next_task()
      end
      local ok, err = pcall(pending, done)
      if not ok then
        log.err("Link update failed: %s", err)
        done()
      end
    end
    if opts and opts.immediate and not vim.in_fast_event() then
      execute()
    else
      vim.schedule(execute)
    end
  end
  if not queue.running then
    next_task()
  end
end

return M
