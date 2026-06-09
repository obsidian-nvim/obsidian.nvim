local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local Path = require "obsidian.path"
local api = require "obsidian.api"
local client = require "obsidian.sync.client"
local sync = require "obsidian.sync"
local status = require "obsidian.sync.status"

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
  client.invalidate_vaults_cache()
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

T["client.list_remote parsing"]["should parse obsidian-headless output"] = function()
  client.invalidate_vaults_cache()
  local stdout = [[
Fetching vaults...

Vaults:
  abcdef0123456789  "Vault One"  (us-east)

Shared vaults:
  123456789abcdef0  "Shared Vault"  (eu)
]]

  local orig_run = client.run
  client.run = function()
    return { code = 0, stdout = stdout, stderr = "" }
  end

  local remotes = client.list_remote()
  eq(2, #remotes)
  eq("abcdef0123456789", remotes[1].hash)
  eq("Vault One", remotes[1].name)
  eq("123456789abcdef0", remotes[2].hash)
  eq("Shared Vault", remotes[2].name)

  client.run = orig_run
end

T["client.list_remote parsing"]["should return empty on nil stdout"] = function()
  client.invalidate_vaults_cache()
  local orig_run = client.run
  client.run = function()
    return { code = 0, stdout = nil, stderr = "" }
  end

  local remotes = client.list_remote()
  eq(0, #remotes)

  client.run = orig_run
end

T["client.list_remote parsing"]["should cache remote vaults"] = function()
  client.invalidate_vaults_cache()
  local calls = 0
  local orig_run = client.run
  client.run = function()
    calls = calls + 1
    return { code = 0, stdout = "abcdef0123456789 Vault One", stderr = "" }
  end

  local remotes = client.list_remote()
  local cached = client.list_remote()
  eq(1, calls)
  eq(remotes, cached)

  client.run = orig_run
end

T["client.run auth handling"] = new_set()

T["client.run auth handling"]["should prompt login only for actual login errors"] = function()
  local orig_cli = rawget(client, "cli")
  local orig_confirm = api.confirm
  local orig_login = client.login
  local calls = 0
  local confirms = 0
  local logins = 0

  client.cli = {
    run_sync = function()
      calls = calls + 1
      if calls == 1 then
        return { code = 2, stdout = "", stderr = 'No account logged in. Run "ob login" first.' }
      end
      return { code = 0, stdout = "ok", stderr = "" }
    end,
  }
  api.confirm = function()
    confirms = confirms + 1
    return "Yes"
  end
  client.login = function()
    logins = logins + 1
    return true
  end

  local out = client.run("sync-list-remote", {})
  eq(0, out.code)
  eq(2, calls)
  eq(1, confirms)
  eq(1, logins)

  client.cli = orig_cli
  api.confirm = orig_confirm
  client.login = orig_login
end

T["client.run auth handling"]["should not prompt login for password validation errors"] = function()
  local orig_cli = rawget(client, "cli")
  local orig_confirm = api.confirm
  local orig_login = client.login
  local calls = 0
  local confirms = 0

  client.cli = {
    run_sync = function()
      calls = calls + 1
      return { code = 2, stdout = "", stderr = "Failed to validate password." }
    end,
  }
  api.confirm = function()
    confirms = confirms + 1
    return "Yes"
  end
  client.login = function()
    error "login should not be called"
  end

  local out = client.run("sync-setup", {})
  eq(2, out.code)
  eq(1, calls)
  eq(0, confirms)

  client.cli = orig_cli
  api.confirm = orig_confirm
  client.login = orig_login
end

T["client.setup"] = new_set()

T["client.setup"]["should retry password validation failures with an E2E password"] = function()
  local orig_run = client.run
  local orig_inputsecret = vim.fn.inputsecret
  local calls = {}

  client.run = function(subcmd, flags)
    table.insert(calls, { subcmd = subcmd, flags = vim.deepcopy(flags) })
    if #calls == 1 then
      return { code = 2, stdout = "", stderr = "Failed to validate password." }
    end
    return { code = 0, stdout = "ok", stderr = "" }
  end
  vim.fn.inputsecret = function(prompt)
    eq("End-to-end encryption password: ", prompt)
    return "vault-password"
  end

  local out = client.setup("abc123", "/home/user/vault")
  eq(0, out.code)
  eq(2, #calls)
  eq("sync-setup", calls[1].subcmd)
  eq("abc123", calls[1].flags.vault)
  eq("/home/user/vault", calls[1].flags.path)
  eq(nil, calls[1].flags.password)
  eq("vault-password", calls[2].flags.password)

  client.run = orig_run
  vim.fn.inputsecret = orig_inputsecret
end

T["obsidian_backend.build_linked_map"] = new_set()

T["obsidian_backend.build_linked_map"]["should map local vaults to remote names"] = function()
  local backend = require "obsidian.sync.backends.obsidian"

  local local_vaults = {
    ["/home/user/vault1"] = { hash = "abc123", host = "desktop" },
    ["/home/user/vault2"] = { hash = "def456", host = "laptop" },
  }

  local remotes = {
    { hash = "abc123", name = "Main Vault" },
    { hash = "def456", name = "Work Vault" },
  }

  local linked = backend.build_linked_map(local_vaults, remotes)
  eq("Main Vault", linked["/home/user/vault1"])
  eq("Work Vault", linked["/home/user/vault2"])
end

T["obsidian_backend.build_linked_map"]["should use hash when remote not found"] = function()
  local backend = require "obsidian.sync.backends.obsidian"

  local local_vaults = {
    ["/home/user/vault1"] = { hash = "abc123", host = "desktop" },
    ["/home/user/vault2"] = { hash = "xyz999", host = "tablet" },
  }

  local remotes = {
    { hash = "abc123", name = "Main Vault" },
  }

  local linked = backend.build_linked_map(local_vaults, remotes)
  eq("Main Vault", linked["/home/user/vault1"])
  eq("xyz999", linked["/home/user/vault2"])
end

T["obsidian_backend.build_linked_map"]["should handle empty remotes"] = function()
  local backend = require "obsidian.sync.backends.obsidian"

  local local_vaults = {
    ["/home/user/vault"] = { hash = "abc123", host = "desktop" },
  }

  local linked = backend.build_linked_map(local_vaults, {})
  eq("abc123", linked["/home/user/vault"])
end

T["obsidian_backend.build_linked_map"]["should handle nil remotes"] = function()
  local backend = require "obsidian.sync.backends.obsidian"

  local local_vaults = {
    ["/home/user/vault"] = { hash = "abc123", host = "desktop" },
  }

  local linked = backend.build_linked_map(local_vaults, nil)
  eq("abc123", linked["/home/user/vault"])
end

T["obsidian_backend.build_linked_map"]["should handle empty local vaults"] = function()
  local backend = require "obsidian.sync.backends.obsidian"
  local linked = backend.build_linked_map({}, {})
  eq(0, #vim.tbl_keys(linked))
end

T["status.set"] = new_set()

T["status.set"]["should set status to synced"] = function()
  status.set "synced"
  eq("󰸞", status.state.icon)
  status.set "syncing"
  eq("󰑓", status.state.icon)
  status.set "error"
  eq("󰅙", status.state.icon)
  status.set "paused"
  eq("󰏤", status.state.icon)
end

T["status.set"]["should use obsidian highlight groups"] = function()
  status.set "synced"
  eq("ObsidianSyncSynced", status.color())
  status.set "syncing"
  eq("ObsidianSyncSyncing", status.color())
  status.set "error"
  eq("ObsidianSyncError", status.color())
  status.set "paused"
  eq("ObsidianSyncPaused", status.color())
end

T["runner.append_log"] = new_set()

T["runner.append_log"]["should notify and set error status on error lines"] = function()
  local runner = require "obsidian.sync.runner"
  local log = require "obsidian.log"

  local orig_err = log.err
  local errors = {}
  log.err = function(msg, ...)
    table.insert(errors, string.format(msg, ...))
  end

  local dir = "/tmp/test-vault-error"
  status.set "synced"

  runner.append_log(dir, "Connecting...")
  eq("syncing", status.state.kind)

  runner.append_log(
    dir,
    table.concat({
      "Disconnected from server",
      "Error: Unable to connect to server.",
      "    at p.onclose (/path/to/cli.js:146:3927)",
      "    at WebSocket.dispatchEvent (node:internal/event_target:776:26)",
    }, "\n")
  )

  eq("error", status.state.kind)
  eq(1, #errors)
  eq("Sync error: Unable to connect to server.", errors[1])

  -- repeated identical errors should not notify again right away
  runner.append_log(dir, "Error: Unable to connect to server.")
  eq(1, #errors)

  -- but a different error should
  runner.append_log(dir, "Error: Something else went wrong.")
  eq(2, #errors)
  eq("Sync error: Something else went wrong.", errors[2])

  log.err = orig_err
  runner.logs[dir] = nil
  status.set "paused"
end

T["runner.append_log"]["should still record error and trace lines in the log"] = function()
  local runner = require "obsidian.sync.runner"
  local log = require "obsidian.log"

  local orig_err = log.err
  log.err = function() end

  local dir = "/tmp/test-vault-log"
  runner.append_log(dir, "Error: Some failure.\n    at somewhere (file.js:1:1)")

  eq(2, #runner.logs[dir])
  eq(true, runner.logs[dir][1]:find("Error: Some failure.", 1, true) ~= nil)
  eq(true, runner.logs[dir][2]:find("at somewhere", 1, true) ~= nil)

  log.err = orig_err
  runner.logs[dir] = nil
  status.set "paused"
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
