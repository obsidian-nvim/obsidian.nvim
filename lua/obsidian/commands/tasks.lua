-- TODO: Use config settings for icons
local task_configs = {
  -- in progress
  ["/"] = { char = " ", order = 0, name = "in progress", hl_group = "ObsidianRightArrow" },
  -- todo
  [" "] = { char = "󰄱 ", order = 1, name = "todo", hl_group = "ObsidianTodo" },
  -- done
  ["x"] = { char = " ", order = 2, name = "done", hl_group = "ObsidianDone" },
  -- cancelled
  ["-"] = { char = " ", order = 3, name = "cancelled", hl_group = "ObsidianTilde" },
}

-- Map states by name for quick lookup
local states = {}
for _, config in pairs(task_configs or {}) do
  states[config.name] = config
end

--- Fetch the next task state in a cycle
---@param current_state string?
---@return string? next_state
local function get_next_state(current_state)
  local state_names = vim.tbl_keys(states)
  -- sort state names by order
  table.sort(state_names, function(a, b)
    return (states[a].order or 0) < (states[b].order or 0)
  end)
  for i, name in ipairs(state_names) do
    if name == current_state then
      return state_names[i % #state_names + 1]
    end
  end
  return state_names[1] -- Default to first state if none found
end

--- Show tasks with optional filtering
---@param client obsidian.Client
---@param data table
local function showTasks(client, data)
  assert(client, "Client is required")

  local filter = data.fargs[1]
  local picker = assert(client:picker(), "No picker configured")

  local tasks = client:find_tasks()
  local toShow = {}

  -- TODO: Hide filename, show only the task
  for _, task in ipairs(tasks) do
    local tStatus = task_configs[task.status]
    if tStatus and (not filter or tStatus.name == filter) then
      table.insert(toShow, {
        display = string.format(" %s", task.description),
        filename = task.path,
        lnum = task.line,
        icon = tStatus.char,
      })
    end
  end

  picker:pick(toShow, {
    prompt_title = filter and (filter .. " tasks") or "tasks",
    query_mappings = {
      ["<C-n>"] = {
        desc = "Toggle task status",
        callback = function()
          local next_state_name = get_next_state(filter)
          showTasks(client, { fargs = { next_state_name } })
        end,
      },
    },
  })
end

return showTasks
