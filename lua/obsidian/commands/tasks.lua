---@class CheckboxConfig
---@field name string
---@field order integer

-- Build the list of task status names sorted by order
---@param checkbox_config table<string,CheckboxConfig>
local function get_task_status_names(checkbox_config)
  -- index by status name
  ---@type table<string, CheckboxConfig>
  local task_by_status_name = {}
  local status_names = {}
  for _, c in pairs(checkbox_config) do
    task_by_status_name[c.name] = c
    status_names[#status_names + 1] = c.name
  end

  -- sort list of status names
  table.sort(status_names, function(a, b)
    return (task_by_status_name[a].order or 0) < (task_by_status_name[b].order or 0)
  end)

  return status_names
end

---@param current string|nil
---@param status_names table<integer, string>
local function get_next_status(current, status_names)
  for i, v in ipairs(status_names) do
    if v == current then
      return status_names[i + 1]
    end
  end
  return status_names[1]
end

--- Show tasks with optional filtering
---@param client obsidian.Client
---@param data table
local function showTasks(client, data)
  assert(client, "Client is required")

  local filter = data.fargs[1]
  local picker = assert(client:picker(), "No picker configured")

  local checkboxes = client.opts.ui.checkboxes
  local status_names = get_task_status_names(checkboxes)

  local tasks = client:find_tasks()
  local toShow = {}

  -- TODO: Hide filename, show only the task
  for _, task in ipairs(tasks) do
    local tStatus = checkboxes[task.status]
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
          local next_state_name = get_next_status(filter, status_names)
          showTasks(client, { fargs = { next_state_name } })
        end,
      },
    },
  })
end

return showTasks
