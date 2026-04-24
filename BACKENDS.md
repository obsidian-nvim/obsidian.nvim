# Sync Backends Analysis (from remotely-save)

## Overview

[remotely-save](https://github.com/remotely-save/remotely-save) supports 15+ storage services. This document analyzes which can become obsidian.nvim backends, ranked by ease of implementation and value.

**Key Insight**: Most remotely-save backends can be covered by a single **`rclone` backend** — rclone is a mature CLI tool supporting all major services and fits the existing CLI-wrapper pattern perfectly.

---

## Ranked Backends

### 1. 🥇 rclone (covers 10+ services)

**Covers**: S3 (R2/B2/MinIO/Storj/Tencent COS/upyun), Dropbox, OneDrive, WebDAV (NextCloud/InfiniCloud/Synology/dufs/AList/NutStore/OMV/Nginx/Apache/Caddy), Google Drive, Box, pCloud, Yandex Disk, Koofr, Azure Blob

| Metric | Rating | Details |
|--------|---------|---------|
| **Ease** | 🟢 High | Single CLI to wrap, same pattern as `git` backend (`vim.system("rclone ...")`) |
| **Value** | 🟢 Very High | One backend covers 90% of remotely-save's supported services |
| **Caveats** | - Requires separate `rclone` install<br>- OAuth services (Dropbox/OneDrive) need initial `rclone config` in terminal<br>- Encryption needs extra `rclone crypt` setup |
| **Fit to Spec** | ✅ Perfect match | Implements all required methods:<br>- `is_configured`: Check `rclone config show` for remote<br>- `sync_once`: `rclone sync <local> <remote:path>`<br>- `start`: Poll with `rclone sync` loop<br>- `pause`: Stop poll timer<br>- `setup`: Guide user to create rclone remote<br>- `caps = { remote_catalog = false }` |

**Config Example**:
```lua
sync = {
  backend = "rclone",
  rclone = {
    remote = "my-s3-remote",  -- rclone remote name
    path = "obsidian-vault",  -- remote subpath
    crypt = false,  -- enable rclone crypt
  },
}
```

**Implementation**: See `lua/obsidian/sync/backends/rclone.lua`

---

### 2. 🥈 Standalone S3 (without rclone)

**Covers**: AWS S3, Cloudflare R2, Backblaze B2, MinIO, Storj, Tencent COS, upyun

| Metric | Rating | Details |
|--------|---------|---------|
| **Ease** | 🟡 Medium | Use `aws s3` CLI or `s3cmd`, but rclone is more unified |
| **Value** | 🟢 High | S3-compatible storage is cheap and popular for self-hosting |
| **Caveats** | - Requires S3 credentials (access key, secret)<br>- Less unified than rclone<br>- No built-in encryption |
| **Fit to Spec** | ✅ Good | Same CLI-wrapper pattern, `aws s3 sync` works identically to rclone |

**When to use**: If you want to avoid rclone dependency and only need S3-compatible storage.

---

### 3. 🥉 WebDAV (standalone, no rclone)

**Covers**: NextCloud, Synology, dufs, AList, NutStore, OMV, Nginx, Apache, Caddy

| Metric | Rating | Details |
|--------|---------|---------|
| **Ease** | 🟡 Medium | Use `cadaver` or `curl`, but rclone is easier |
| **Value** | 🟡 Medium | WebDAV is common for self-hosted setups, but rclone already covers it |
| **Caveats** | - WebDAV servers vary in compatibility<br>- No CORS issues (CLI avoids browser limits that remotely-save has) |
| **Fit to Spec** | ✅ Good | CLI tools exist (`cadaver`, `curl`), fits wrapper pattern |

**When to use**: If you have a specific WebDAV server that doesn't work well with rclone.

---

### 4. Webdis (Experimental)

**Covers**: Webdis REST servers

| Metric | Rating | Details |
|--------|---------|---------|
| **Ease** | 🔴 Low | No official CLI, need to write custom REST client |
| **Value** | 🔴 Low | Experimental, niche use case |
| **Caveats** | - Unstable API<br>- No existing CLI tools<br>- Requires custom implementation |
| **Fit to Spec** | ⚠️ Poor | Requires custom CLI implementation, breaks CLI-wrapper pattern |

**When to use**: Only if you're already using Webdis and want to experiment.

---

## Current Sync Spec (for reference)

```lua
---@class obsidian.sync.Backend
---@field name string
---@field caps table<string, boolean>
---@field is_configured fun(ws: obsidian.Workspace, cache: any?): boolean
---@field start fun(dir: string, opts?: { silent: boolean? })
---@field pause fun(dir: string)
---@field sync_once fun(dir: string, opts?: { silent: boolean? })
---@field setup fun(ws: obsidian.Workspace)
---@field disconnect fun(ws: obsidian.Workspace)
---@field log fun(dir: string)
```

**Config Options** (from `lua/obsidian/config/default.lua`):
```lua
sync = {
  enabled = false,
  backend = "obsidian",  -- "obsidian" | "git" | "rclone"
  trigger = "continuous",  -- "continuous" | "on_write" | "manual"
  write_debounce_ms = 2000,
  mode = nil,  -- "bidirectional" | "pull-only" | "mirror-remote"
  conflict_strategy = "merge",  -- "merge" | "conflict"
  file_types = { "image", "audio", "video", "pdf", "unsupported" },
  configs = nil,
  excluded_folders = {},
  device_name = nil,
  config_dir = ".obsidian",
}
```

---

## Conflict Handling

All backends should follow the same conflict handling pattern as `git.lua`:

| Strategy | Behavior |
|----------|-----------|
| `merge` (default) | Use backend's default behavior (rclone overwrites, git rebases) |
| `conflict` | Create conflict copies per Obsidian naming rules:<br>`file (Conflicted copy device timestamp).md` |

**Obsidian conflict naming** (from `git.lua:45-75`):
```lua
function conflict_name(path, dir)
  -- Returns: "stem (Conflicted copy device_name timestamp).ext"
end
```

---

## Recommendation

**Implement the `rclone` backend first** — it delivers 10x value for 1x effort by covering almost all remotely-save compatible services in a single backend that fits the existing CLI-wrapper pattern perfectly.

**Implementation priority**:
1. ✅ rclone (covers 90% of use cases)
2. ⚠️ Standalone S3 (only if rclone is not an option)
3. ❌ Skip WebDAV standalone (rclone covers it)
4. ❌ Skip Webdis (too experimental)
