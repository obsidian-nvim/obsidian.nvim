local sync = require "obsidian.sync"

local function get_workspace_path()
  local ws = Obsidian.workspace
  if ws and ws.root then
    return tostring(ws.root)
  end
  return nil
end

---@param data obsidian.CommandArgs
return function(_)
  local h = sync.new()
  if not h or not h:check_installed() then
    vim.notify(
      "obsidian-headless not found. Run 'npm install obsidian-headless' in the plugin folder.",
      vim.log.levels.ERROR
    )
    return
  end

  local workspace_path = get_workspace_path()
  if not workspace_path then
    vim.notify("No active workspace. Open a vault first.", vim.log.levels.ERROR)
    return
  end

  local watch = Obsidian.opts.headless_sync and Obsidian.opts.headless_sync.watch

  local function do_sync()
    vim.notify("Syncing vault...", vim.log.levels.INFO)
    h:sync(workspace_path, watch)
  end

  if h:is_configured(workspace_path) then
    do_sync()
  else
    local remote = h:list_remote()
    if remote and #remote == 1 then
      h:setup(remote[1].name, workspace_path)
      do_sync()
    elseif remote and #remote > 1 then
      vim.ui.select(remote, {
        prompt = "Select vault to sync:",
        format_item = function(item)
          return item.name
        end,
      }, function(choice)
        if choice then
          h:setup(choice.name, workspace_path)
          do_sync()
        end
      end)
    else
      vim.ui.input({ prompt = "Vault name to sync: " }, function(vault_name)
        if not vault_name or vim.trim(vault_name) == "" then
          return
        end
        h:setup(vault_name, workspace_path)
        do_sync()
      end)
    end
  end
end
