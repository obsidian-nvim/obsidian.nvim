# YAOS as obsidian.nvim Sync Backend - Feasibility Analysis

## YAOS Overview

**YAOS** (Yet Another Obsidian Sync) is a zero-terminal, real-time sync engine for Obsidian powered by Cloudflare Workers and Yjs CRDTs.

### How It Works

1. **Monolithic Y.Doc**: Each vault maps to a single `Y.Doc` containing all file metadata, folder structures, and per-file `Y.Text` CRDTs
2. **Cloudflare Durable Objects**: Each vault maps to one sync room with persistent CRDT state
3. **Real-time WebSocket Sync**: `wss://<host>/vault/sync/<vaultId>?token=<token>`
4. **Filesystem Bridge**: Bidirectional sync between disk and CRDT using:
   - Dirty-set drain loop (coalescing path-based events)
   - Per-path serialization for outbound writes
   - Content-addressed state acknowledgment (SHA-256 hash matching)
5. **Attachments**: Content-addressed R2 storage with bounded fan-out
6. **Snapshots**: Daily automatic gzipped CRDT archives

### Key Design Decisions

- **ACID Transactions**: Folder renames are atomic across all files via `ydoc.transact()`
- **Content-Acknowledged Suppression**: Replaced time-based heuristics with state verification to avoid self-echo loops
- **50MB Text Limit**: Monolithic design ceiling; ~1.9% CRDT overhead observed in practice

---

## Current obsidian.nvim Sync Architecture

### Backend Interface (`lua/obsidian/sync/init.lua:5-14`)

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

### Existing Backends

| Backend    | Implementation                | Pattern                           |
| ---------- | ----------------------------- | --------------------------------- |
| `obsidian` | Wraps `obsidian-headless` CLI | CLI subprocess via `vim.system()` |
| `git`      | Pure git operations           | CLI subprocess via `vim.system()` |

Both backends follow the **CLI wrapper pattern** - they shell out to external tools.

### Backend Registration

```lua
-- lua/obsidian/sync/init.lua:20-27
local builtin_loaders = {
  obsidian = function()
    return require "obsidian.sync.backends.obsidian"
  end,
  git = function()
    return require "obsidian.sync.backends.git"
  end,
}
```

Custom backends register via `M.register(name, backend)`.

---

## Feasibility Analysis

### Fundamental Mismatch

YAOS is architected as an **Obsidian plugin** (TypeScript, browser APIs, IndexedDB) with a Cloudflare Worker backend. obsidian.nvim backends are **Lua modules that wrap CLI tools**.

```
┌─────────────────────────────────────────────────────────────┐
│                    YAOS Architecture                        │
│  Obsidian Plugin (TS) ←→ Cloudflare Worker (WS + Yjs)    │
│       ↓                                                     │
│  IndexedDB (offline queue)                                 │
│       ↓                                                     │
│  Filesystem Bridge (CodeMirror bindings, event handling)   │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│              obsidian.nvim Backend Pattern                  │
│  Lua Module → CLI Wrapper → External Process               │
│  Examples: git CLI, obsidian-headless CLI                  │
└─────────────────────────────────────────────────────────────┘
```

### Challenge Matrix

| Challenge                 | Impact    | Effort      | Details                                                       |
| ------------------------- | --------- | ----------- | ------------------------------------------------------------- |
| **No standalone CLI**     | 🔴 High   | 🔴 Enormous | YAOS has no CLI; would need to extract sync logic from plugin |
| **Yjs in Lua**            | 🔴 High   | 🔴 Enormous | No native Lua Yjs implementation; would need protocol port    |
| **WebSocket client**      | 🟡 Medium | 🟡 Moderate | Need Lua WS library (e.g., `lua-websockets`)                  |
| **Filesystem bridge**     | 🔴 High   | 🔴 Enormous | ~500 lines of complex event→CRDT logic with browser APIs      |
| **IndexedDB dependency**  | 🟡 Medium | 🟡 Moderate | Offline queue needs alternative (SQLite, flat files)          |
| **Token auth flow**       | 🟢 Low    | 🟢 Easy     | Standard Bearer token auth                                    |
| **CRDT state management** | 🔴 High   | 🔴 Enormous | Durable Object state vs local Lua state                       |

### API Surface Available

YAOS Server Endpoints (`server/README.md`):

```
WebSocket:
  wss://<host>/vault/sync/<vaultId>?token=<setup-token>

Blob APIs:
  POST /vault/<vaultId>/blobs/exists
  PUT  /vault/<vaultId>/blobs/<sha256>
  GET  /vault/<vaultId>/blobs/<sha256>

Snapshot APIs:
  POST /vault/<vaultId>/snapshots/maybe
  POST /vault/<vaultId>/snapshots
  GET  /vault/<vaultId>/snapshots
  GET  /vault/<vaultId>/snapshots/<snapshotId>

Debug:
  GET /vault/<vaultId>/debug/recent
```

All HTTP endpoints require `Authorization: Bearer <token>`.

---

## Implementation Approaches

### Approach 1: Native Lua YAOS Client

Write a complete Yjs protocol handler + WebSocket client in Lua.

**Pros:**

- Native integration with obsidian.nvim
- No external dependencies beyond WS library

**Cons:**

- Enormous effort (~3000+ lines)
- Yjs binary protocol implementation
- Untested in Lua ecosystem
- Filesystem bridge reimplementation

**Verdict**: ❌ Not practical

---

### Approach 2: Standalone YAOS CLI

Extract YAOS sync logic into a standalone CLI tool (like `obsidian-headless`).

**Architecture:**

```
obsidian.nvim → yaos-cli (subprocess) → Cloudflare Worker (WS)
```

**Pros:**

- Fits existing backend pattern perfectly
- Reuses proven Yjs implementation
- Follows `obsidian-headless` model

**Cons:**

- Significant refactoring of YAOS plugin
- Need to extract: Yjs handling, WS client, filesystem bridge
- Would need to maintain separate CLI project

**Tasks:**

1. Create `yaos-cli` project (Node.js/TypeScript)
2. Extract from plugin: `Y.Doc` management, WS client, auth
3. Implement filesystem bridge in Node.js
4. Expose CLI commands: `sync`, `sync --once`, `setup`, `disconnect`
5. Write Lua backend wrapping the CLI

**Verdict**: ✅ Most practical approach

---

### Approach 3: Hybrid Proxy

Minimal CLI that bridges Lua backend ↔ YAOS plugin via IPC.

**Architecture:**

```
obsidian.nvim → minimal-cli → spawn YAOS plugin code → Cloudflare Worker
```

**Pros:**

- Less extraction than Approach 2
- Can reuse plugin code directly

**Cons:**

- Fragile IPC boundaries
- Still need filesystem bridge in Node.js
- Odd architectural pattern

**Verdict**: ⚠️ Possible but awkward

---

## Extensibility Test Results

YAOS serves as an excellent **extreme case** for testing sync backend extensibility:

### What Works Well

✅ Backend interface is generic enough to accommodate new backends
✅ Registration system (`M.register()`) allows custom backends without core changes
✅ Configuration system supports backend-specific options (`sync.configs`)

### What Breaks

❌ **CLI wrapper assumption**: All backends assume they can shell out to a CLI tool
❌ **Process model**: Backends assume synchronous/async subprocess execution
❌ **No CRDT support**: Interface has no concept of real-time collaborative state
❌ **No WebSocket pattern**: Backends don't handle persistent connections

### Required Interface Extensions

To properly support YAOS-like backends:

```lua
---@class obsidian.sync.Backend
---@field name string
---@field caps table<string, boolean>
---@field supports_realtime boolean?  -- New: CRDT/WS backends
---@field is_configured fun(ws: obsidian.Workspace, cache: any?): boolean
---@field start fun(dir: string, opts?: { silent: boolean? })
---@field pause fun(dir: string)
---@field sync_once fun(dir: string, opts?: { silent: boolean? })
---@field setup fun(ws: obsidian.Workspace)
---@field disconnect fun(ws: obsidian.Workspace)
---@field log fun(dir: string)
---@field on_file_change? fun(path: string, content: string)  -- New: for CRDT backends
---@field get_status? fun(): obsidian.sync.Status  -- New: real-time status
```

---

## Verdict

### Feasibility: 🟡 MODERATE (with significant effort)

| Aspect              | Rating      | Notes                                |
| ------------------- | ----------- | ------------------------------------ |
| Near-term viability | 🔴 LOW      | No path without major work           |
| Architecture fit    | 🟡 MODERATE | Interface extensible but assumes CLI |
| Effort required     | 🔴 HIGH     | 2-4 weeks for Approach 2             |
| Maintenance burden  | 🟡 MODERATE | Would need to track YAOS updates     |

### Recommendation

**For research/extensibility testing**: Mark YAOS as a known extreme case that the current interface cannot handle natively. Document that:

1. The CLI wrapper pattern is a deliberate design choice for simplicity
2. Real-time CRDT backends would need interface extensions
3. The current architecture favors simplicity over supporting all possible sync models

**For actual implementation**: Approach 2 (Standalone YAOS CLI) is the only practical path. This would be a separate project (`yaos-cli`) that:

1. Extracts sync logic from the YAOS Obsidian plugin
2. Implements a `obsidian-headless`-like CLI interface
3. Allows obsidian.nvim to treat YAOS like any other backend

### Final Note

YAOS represents the **upper bound of sync complexity** - real-time CRDTs, WebSocket connections, filesystem bridging, and offline queues. The fact that the current interface doesn't support it natively is not a design flaw, but rather a reflection that:

- Most users want simple file-based sync (git, Dropbox-style)
- CLI wrappers are the most maintainable pattern for Neovim plugins
- Real-time collaborative editing is a different product category (like Figma vs git)

The extensibility test succeeds in proving the interface is clean, but reveals its intentional scope boundaries.
