local Sync = require "obsidian.sync"
local api = require "obsidian.api"

return function()
  local sync = Sync.new()
  if not sync or not sync:check_installed() then
    vim.notify(
      "obsidian-headless not found. Run 'npm install obsidian-headless' in the plugin folder.",
      vim.log.levels.ERROR
    )
    return
  end

  local workspace_path = tostring(api.resolve_workspace_dir())

  if not workspace_path then
    vim.notify("No active workspace. Open a vault first.", vim.log.levels.ERROR)
    return
  end

  local sync_opts = Obsidian.opts.sync or {}
  local watch = sync_opts.watch

  local function do_sync()
    sync:sync(workspace_path, watch)
  end

  if sync:is_configured(workspace_path) then
    do_sync()
    return
  end

  local function do_setup_and_sync(vault_id_or_name) end

  local remote = sync:list_remote()

  if not remote or #remote == 0 then -- no available remotes, prompt to create new one
    create_new_remote()
  elseif #remote == 1 then -- only one remote, confirm to use it
    if api.confirm("One remote vault found: " .. remote[1].name .. ". Sync with it?") then
      do_setup_and_sync(remote[1].hash)
    end
  else
    vim.ui.select(remote, {
      prompt = "Select vault to sync:",
      format_item = function(item)
        return item.name
      end,
    }, function(choice)
      if choice then
        do_setup_and_sync(choice.hash)
      end
    end)
  end
end
