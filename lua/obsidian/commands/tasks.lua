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
  local status_names = client:get_task_status_names()

  local tasks = client:find_tasks()
  local toShow = {}

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
