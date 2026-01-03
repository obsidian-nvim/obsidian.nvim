local root = "https://127.0.0.1:27124/"
local token = "c17187f6eca856ce259cebbce6ba672c5e99ebd7081ae15eccd2736f5cd49b65"

---@alias obsidian.rest.command { id: string, name: string }

local function check_if_obsidian()
  local out = vim
    .system({
      "curl",
      root .. "commands",
      "-k",
      "-H",
      "Authorization: Bearer " .. token,
    })
    :wait()
  return out.code == 0
end

---@return obsidian.rest.command[]
local function list_commands()
  local out = vim
    .system({
      "curl",
      root .. "commands",
      "-k",
      "-H",
      "Authorization: Bearer " .. token,
    })
    :wait()
  assert(out.code == 0, "failed to make local rest api request")
  return vim.json.decode(out.stdout).commands
end

---@param cmd obsidian.rest.command
local function run_command(cmd)
  local out = vim
    .system({
      "curl",
      root .. "commands/" .. cmd.id,
      "-k",
      "-H",
      "Authorization: Bearer " .. token,
      "-X",
      "POST",
    })
    :wait()
  assert(out.code, "failed to make local rest api request")
end

local function pick()
  local commands = list_commands()

  ---@type obsidian.PickerEntry[]
  local entries = {}

  for _, cmd in ipairs(commands) do
    entries[#entries + 1] = {
      text = cmd.name,
      user_data = cmd,
    }
  end

  Obsidian.picker.pick(entries, {
    callback = function(entry)
      local cmd = entry.user_data
      run_command(cmd)
    end,
  })
end

if not check_if_obsidian() then
  -- TODO:
  vim
    .system(
      { "xvfb-run", "-a", "obsidian" },
      { detach = true },
      vim.schedule_wrap(function()
        pick()
      end)
    )
    :wait()
else
  pick()
end
