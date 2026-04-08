local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local Path = require "obsidian.path"
local client = require "obsidian.sync.client"
local sync = require "obsidian.sync"

local T = new_set()

T["client.list_local parsing"] = new_set()

-- TODO: not needed once https://github.com/obsidianmd/obsidian-headless/issues/6

T["client.list_local parsing"]["should parse single vault"] = function()
  client.invalidate_vaults_cache()
  local stdout = [[
1234567890abcdef1234567890abcdef12345678
  Path: /home/user/vault
  Host: desktop
]]

  local mock_out = { code = 0, stdout = stdout, stderr = "" }

  local orig_run = client.run
  client.run = function()
    return mock_out
  end

  local vaults = client.list_local()
  eq(1, #vim.tbl_keys(vaults))
  eq("/home/user/vault", vim.tbl_keys(vaults)[1])
  eq("1234567890abcdef1234567890abcdef12345678", vaults["/home/user/vault"].hash)
  eq("desktop", vaults["/home/user/vault"].host)

  client.run = orig_run
end

T["client.list_local parsing"]["should parse multiple vaults"] = function()
  client.invalidate_vaults_cache()
  local stdout = [[
abcdef0123456789abcdef0123456789abcdef01
  Path: /home/user/vault1
  Host: desktop
123456789abcdef0123456789abcdef01234567
  Path: /home/user/vault2
  Host: laptop
]]

  local mock_out = { code = 0, stdout = stdout, stderr = "" }
  local orig_run = client.run
  client.run = function()
    return mock_out
  end

  local vaults = client.list_local()
  eq(2, #vim.tbl_keys(vaults))
  eq("abcdef0123456789abcdef0123456789abcdef01", vaults["/home/user/vault1"].hash)
  eq("desktop", vaults["/home/user/vault1"].host)
  eq("123456789abcdef0123456789abcdef01234567", vaults["/home/user/vault2"].hash)
  eq("laptop", vaults["/home/user/vault2"].host)

  client.run = orig_run
end

T["client.list_local parsing"]["should return empty on error"] = function()
  client.invalidate_vaults_cache()
  local orig_run = client.run
  client.run = function()
    return { code = 1, stdout = "", stderr = "error" }
  end

  local vaults = client.list_local()
  eq(0, #vim.tbl_keys(vaults))

  client.run = orig_run
end

T["client.list_local parsing"]["should return empty on nil stdout"] = function()
  client.invalidate_vaults_cache()
  local orig_run = client.run
  client.run = function()
    return { code = 0, stdout = nil, stderr = "" }
  end

  local vaults = client.list_local()
  eq(0, #vim.tbl_keys(vaults))

  client.run = orig_run
end

T["client.list_remote parsing"] = new_set()

T["client.list_remote parsing"]["should parse remote vault list"] = function()
  local stdout = [[
abcdef0123456789 Vault One
123456789abcdef0 My Other Vault
]]

  local mock_out = { code = 0, stdout = stdout, stderr = "" }
  local orig_run = client.run
  client.run = function()
    return mock_out
  end

  local remotes = client.list_remote()
  eq(2, #remotes)
  eq("abcdef0123456789", remotes[1].hash)
  eq("Vault One", remotes[1].name)
  eq("123456789abcdef0", remotes[2].hash)
  eq("My Other Vault", remotes[2].name)

  client.run = orig_run
end

T["client.list_remote parsing"]["should return empty on nil stdout"] = function()
  local orig_run = client.run
  client.run = function()
    return { code = 0, stdout = nil, stderr = "" }
  end

  local remotes = client.list_remote()
  eq(0, #remotes)

  client.run = orig_run
end

T["manage.build_linked_map"] = new_set()

T["manage.build_linked_map"]["should map local vaults to remote names"] = function()
  local manage = require "obsidian.sync.manage"

  local local_vaults = {
    ["/home/user/vault1"] = { hash = "abc123", host = "desktop" },
    ["/home/user/vault2"] = { hash = "def456", host = "laptop" },
  }

  local remotes = {
    { hash = "abc123", name = "Main Vault" },
    { hash = "def456", name = "Work Vault" },
  }

  local linked = manage.build_linked_map(local_vaults, remotes)
  eq("Main Vault", linked["/home/user/vault1"])
  eq("Work Vault", linked["/home/user/vault2"])
end

T["manage.build_linked_map"]["should use hash when remote not found"] = function()
  local manage = require "obsidian.sync.manage"

  local local_vaults = {
    ["/home/user/vault1"] = { hash = "abc123", host = "desktop" },
    ["/home/user/vault2"] = { hash = "xyz999", host = "tablet" },
  }

  local remotes = {
    { hash = "abc123", name = "Main Vault" },
  }

  local linked = manage.build_linked_map(local_vaults, remotes)
  eq("Main Vault", linked["/home/user/vault1"])
  eq("xyz999", linked["/home/user/vault2"])
end

T["manage.build_linked_map"]["should handle empty remotes"] = function()
  local manage = require "obsidian.sync.manage"

  local local_vaults = {
    ["/home/user/vault"] = { hash = "abc123", host = "desktop" },
  }

  local linked = manage.build_linked_map(local_vaults, {})
  eq("abc123", linked["/home/user/vault"])
end

T["manage.build_linked_map"]["should handle nil remotes"] = function()
  local manage = require "obsidian.sync.manage"

  local local_vaults = {
    ["/home/user/vault"] = { hash = "abc123", host = "desktop" },
  }

  local linked = manage.build_linked_map(local_vaults, nil)
  eq("abc123", linked["/home/user/vault"])
end

T["manage.build_linked_map"]["should handle empty local vaults"] = function()
  local manage = require "obsidian.sync.manage"
  local linked = manage.build_linked_map({}, {})
  eq(0, #vim.tbl_keys(linked))
end

T["status.set"] = new_set()

T["status.set"]["should set status for a vault path"] = function()
  vim.g.obsidian_sync_status_kind = nil
  ---@diagnostic disable-next-line:undefined-global
  Obsidian = { workspace = { root = Path.new "/home/user/vault" } }
  local status = require "obsidian.sync.status"
  status.set("/home/user/vault", "syncing")
  eq("syncing", vim.g.obsidian_sync_status_kind)
  ---@diagnostic disable-next-line:undefined-global
  Obsidian = nil
end

T["status.set"]["should set status to synced"] = function()
  vim.g.obsidian_sync_status_kind = nil
  ---@diagnostic disable-next-line:undefined-global
  Obsidian = { workspace = { root = Path.new "/home/user/vault" } }
  local status = require "obsidian.sync.status"
  status.set("/home/user/vault", "synced")
  eq("synced", vim.g.obsidian_sync_status_kind)
  ---@diagnostic disable-next-line:undefined-global
  Obsidian = nil
end

T["status.set"]["should not override paused with syncing"] = function()
  vim.g.obsidian_sync_status_kind = "paused"
  ---@diagnostic disable-next-line:undefined-global
  Obsidian = { workspace = { root = Path.new "/home/user/vault" } }
  local status = require "obsidian.sync.status"
  status.set("/home/user/vault", "syncing")
  eq("paused", vim.g.obsidian_sync_status_kind)
  ---@diagnostic disable-next-line:undefined-global
  Obsidian = nil
end

T["init.is_configured"] = new_set()

T["init.is_configured"]["should return true when vault is configured"] = function()
  local vaults = {
    ["/home/user/vault"] = { hash = "abc123", host = "desktop" },
  }

  local ws = { root = Path.new "/home/user/vault", name = "test" }
  eq(true, sync.is_configured(ws, vaults))
end

T["init.is_configured"]["should return false when vault is not configured"] = function()
  local vaults = {
    ["/home/other/vault"] = { hash = "abc123", host = "desktop" },
  }

  local ws = { root = Path.new "/home/user/vault", name = "test" }
  eq(false, sync.is_configured(ws, vaults))
end

T["init.is_configured"]["should return false when vaults is nil and no local vaults"] = function()
  client.invalidate_vaults_cache()

  local orig_run = client.run
  client.run = function()
    return { code = 0, stdout = "", stderr = "" }
  end

  local ws = { root = Path.new "/home/user/vault", name = "test" }
  eq(false, sync.is_configured(ws, nil))

  client.run = orig_run
end

T["init.is_configured"]["should return false when vaults is empty"] = function()
  local ws = { root = Path.new "/home/user/vault", name = "test" }
  eq(false, sync.is_configured(ws, {}))
end

return T
