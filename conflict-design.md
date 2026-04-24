# Sync Conflict Resolution — Design

Backend-agnostic conflict model that mirrors Obsidian Sync's _Create conflict
file_ behavior, applied uniformly across the obsidian-headless and git
backends.

## Goals

1. Shared conflict file format across backends (naming + content split).
2. Git backend detects merge/rebase conflicts and materializes them as
   conflict-copy files instead of leaving the repo in a broken rebase state.
3. Config surface aligned with Obsidian's two modes: merge vs. conflict-copy.
4. Deterministic recipes for reproducing conflicts manually on both backends.

## Background: Obsidian Sync

Source: `conflict.md` (Obsidian Help, `obsidian.md/help/sync/troubleshoot`).

- **Merge mode** (default): markdown files merged with Google's
  diff-match-patch; other files use last-modified-wins; JSON settings merged
  per-key.
- **Create conflict file** mode (since Obsidian 1.9.7): remote version is
  written back to the original path; the local version is preserved alongside
  as:

  ```
  <stem> (Conflicted copy <device-name> <YYYYMMDDHHMM>).<ext>
  ```

  The suffix is inserted **before** the extension. Example:

  ```
  Meeting notes (Conflicted copy MyMacBook2 202411281430).md
  ```

- The setting is **device-specific**. Each client must opt in to conflict-copy
  mode independently.

## Backend interface addition

Extend `obsidian.sync.Backend` with an optional capability flag:

```lua
---@class obsidian.sync.Backend
---@field caps { remote_catalog: boolean, conflict_copy: boolean }
```

Backends that can produce conflict-copy files set `caps.conflict_copy = true`.
Those that can't (or opt not to) leave it false and fall back to surfacing the
error through `sync_log`.

## Config additions

`obsidian.config.SyncOpts.conflict_strategy` already exists
(`"merge"|"conflict"`) but is not wired anywhere. Wire it:

- `"merge"` — backend-native merge. Obsidian backend defers to the headless
  CLI (diff-match-patch). Git backend uses `git pull --rebase --autostash`
  with auto-resolve via recursive strategy; if conflicts remain, abort the
  rebase, log, and set status `paused`. Matches current behavior.
- `"conflict"` — if the backend supports `caps.conflict_copy`, on conflict
  rewrite the working tree so the remote version takes the original path and
  the local version is saved as a conflict-copy file.

Additions:

```lua
sync = {
  ...
  ---@field conflict_strategy "merge"|"conflict"
  conflict_strategy = "merge",

  ---Device name used in conflict file names. Shared with existing
  ---sync.device_name. Fallback order: device_name → hostname → "nvim".
  device_name = nil,
}
```

Naming helper (shared):

```lua
-- obsidian/sync/conflict.lua
local M = {}

---@param path string  absolute path to the conflicting file
---@param device string
---@param when integer?  os.time(), defaults to current
---@return string
function M.conflict_name(path, device, when)
  local ts = os.date("%Y%m%d%H%M", when or os.time())
  local dir = vim.fs.dirname(path)
  local stem, ext = path:match "([^/]+)%.([^./]+)$"
  if not stem then
    -- extensionless file
    stem = vim.fs.basename(path)
    ext = nil
  end
  local suffix = string.format(" (Conflicted copy %s %s)", device, ts)
  if ext then
    return vim.fs.joinpath(dir, stem .. suffix .. "." .. ext)
  end
  return vim.fs.joinpath(dir, stem .. suffix)
end

return M
```

Device resolution:

```lua
local function device_name()
  local opts = Obsidian.opts.sync
  if opts and opts.device_name and opts.device_name ~= "" then
    return opts.device_name
  end
  return (vim.uv or vim.loop).os_gethostname() or "nvim"
end
```

## Git backend: conflict-copy flow

Replace the current `sync_once` flow (`add → commit → pull --rebase → push`)
with an explicit fetch/merge pipeline so we own conflict detection.

### Flow

```
1. git add -A
2. git diff --cached --quiet
   yes changes → git commit -m <msg>
3. git fetch <remote>
4. compute:
     local_head   = HEAD
     remote_head  = <remote>/<branch>
     base         = git merge-base HEAD <remote>/<branch>
5. case:
   - local_head == remote_head                     → nothing to do
   - base == local_head  (we are behind only)      → git merge --ff-only
   - base == remote_head (remote is behind only)   → git push
   - otherwise (diverged) → merge with conflict handling:
       git merge --no-ff --no-commit <remote>/<branch>
       if exit 0:
         git commit -m "sync: merge <remote>/<branch>"
         git push
       else:
         resolve_conflicts()
         git add -A
         git commit -m "sync: merge <remote>/<branch> with conflict copies"
         git push
```

### `resolve_conflicts()`

During a merge, the index holds three stages for each conflicted path:

- `:1:path` — base (common ancestor)
- `:2:path` — ours (local HEAD)
- `:3:path` — theirs (remote)

For every unmerged path reported by `git ls-files -u`:

1. Read ours: `git show :2:<path>` (or from filesystem backup if binary).
2. Read theirs: `git show :3:<path>`.
3. Write theirs to `<path>` (remote wins on the original path — matches
   Obsidian's "original file keeps the remote version").
4. Write ours to `conflict_name(<path>, device, now)`.
5. `git add <path>` and `git add <conflict_name>`.

Edge cases:

- **Delete/modify**:
  - Remote deletes, we modify: our content becomes the conflict copy; the
    original remains deleted. `git add -A` stages both.
  - We delete, remote modifies: remote file is restored at original path;
    conflict copy not produced (our side is empty).
- **Add/add** (same path created on both sides, no base):
  - `:1:` is absent. Fall through the same way: write theirs to path, ours to
    conflict-copy name.
- **Binary files** (attachments): same algorithm — read via `git show` (raw
  bytes), write with `vim.uv.fs_write`. No diff-match-patch needed.
- **File-mode conflicts**: rare; resolve by taking theirs mode.
- **Rename/rename**: surface as error; fall back to `paused` + log. Obsidian
  doesn't document this case either.

### Retry safety

If push fails after conflict resolution (someone pushed again in the window),
recurse: fetch + merge again. Cap at 3 attempts, then abort and log.

### Fallback when `conflict_strategy = "merge"`

Preserve current rebase flow:

```
git pull --rebase --autostash <remote> [<branch>]
```

If rebase conflicts, run `git rebase --abort`, log `rebase aborted, run :Obsidian sync log`, set status `paused`. No partial state left.

## Obsidian backend

The headless CLI already implements both modes. Wire
`Obsidian.opts.sync.conflict_strategy` through `client.set_config` (it maps to
the existing `--conflict-strategy` flag), so the user's choice propagates.

`caps.conflict_copy` is set `true` unconditionally for the obsidian backend —
the CLI produces the conflict file itself.

## Manual test recipes

### Obsidian backend

Two local vaults linked to the same remote, diverging offline edits. Using
the `ob` CLI with separate config dirs so each "device" is independent.

```bash
# One-time
ob login
VAULT_ID=$(ob sync-create-remote --name conflict-test | awk '/Vault ID/ {print $3}')

# Device A
mkdir -p /tmp/device-a/vault
ob --config-dir /tmp/device-a/cfg sync-setup --vault $VAULT_ID --path /tmp/device-a/vault
echo "shared base" > /tmp/device-a/vault/note.md
ob --config-dir /tmp/device-a/cfg sync-config --path /tmp/device-a/vault \
  --device-name device-a --conflict-strategy conflict
(cd /tmp/device-a/vault && ob --config-dir /tmp/device-a/cfg sync)

# Device B (pull the base first, then go "offline")
mkdir -p /tmp/device-b/vault
ob --config-dir /tmp/device-b/cfg sync-setup --vault $VAULT_ID --path /tmp/device-b/vault
ob --config-dir /tmp/device-b/cfg sync-config --path /tmp/device-b/vault \
  --device-name device-b --conflict-strategy conflict
(cd /tmp/device-b/vault && ob --config-dir /tmp/device-b/cfg sync)

# Diverge on the SAME line (merge can't auto-resolve that cleanly; conflict
# strategy produces a separate file regardless)
echo "edit from A" > /tmp/device-a/vault/note.md
echo "edit from B" > /tmp/device-b/vault/note.md

# A syncs first (wins the "remote" position)
(cd /tmp/device-a/vault && ob --config-dir /tmp/device-a/cfg sync)

# B now syncs → should produce a conflict copy
(cd /tmp/device-b/vault && ob --config-dir /tmp/device-b/cfg sync)

ls /tmp/device-b/vault
# Expect: note.md  AND  note (Conflicted copy device-b YYYYMMDDHHMM).md
```

Notes:

- `conflict_strategy = "conflict"` must be set on **device B** (the one
  discovering the conflict). Obsidian creates the copy on whichever client
  detects the collision.
- Touching the same line is what makes diff-match-patch surrender; touching
  non-overlapping lines will silently merge even in `conflict` mode in some
  cases.

### Git backend

Much simpler — any diverging commit to the same file forces a conflict.

```bash
# Bare remote
rm -rf /tmp/remote.git /tmp/a /tmp/b
git init --bare /tmp/remote.git

# Device A
git clone /tmp/remote.git /tmp/a
cd /tmp/a
echo "shared base" > note.md
git add . && git commit -m base && git push -u origin main

# Device B
git clone /tmp/remote.git /tmp/b

# Diverge on same line
cd /tmp/a && echo "edit from A" > note.md && git commit -am A && git push
cd /tmp/b && echo "edit from B" > note.md && git commit -am B

# Trigger sync from /tmp/b in nvim:
#   :Obsidian sync sync      (one-shot)
# Or from lua:
#   require("obsidian.sync").sync_once({ root = "/tmp/b" })

# Expect after run with conflict_strategy = "conflict":
ls /tmp/b
# note.md                                              # contains "edit from A"
# note (Conflicted copy <hostname> YYYYMMDDHHMM).md    # contains "edit from B"
# git log shows a merge commit: "sync: merge origin/main with conflict copies"
```

Extra cases worth manually poking:

- **Delete/modify**: `rm note.md` in A, edit in B. Verify B ends with a
  conflict copy of the local edit while `note.md` stays deleted.
- **Binary**: replace an image on both sides. Verify the conflict copy opens
  correctly (bytes preserved, not text-encoded).
- **Three-way retry**: push a new commit to the remote _after_ B starts
  syncing (race). Verify the retry loop completes within 3 attempts.

## Unit-test hooks

Add under `tests/sync/test_conflict.lua`:

- `conflict_name` over extensions: `.md`, `.png`, no-extension, dotfiles
  (`.obsidian/foo.json`), spaces and parentheses in stem.
- `conflict_name` is stable for a given `when` (snapshot).
- Git backend: run the full recipe against a bare repo in a `tmp_dir` fixture,
  assert both files exist with expected contents, assert the merge commit
  exists, assert status transitions `syncing → synced`.

## Open questions

1. **Two-way conflict copies?** Obsidian only writes the copy on the detecting
   device. Our git implementation does the same (only B creates the copy).
   Sufficient because the "winning" side already has its content at the
   canonical path.
2. **Copy-in-remote opt-in?** Obsidian leaves conflict copies in the vault
   until the user resolves them. Should the sync process itself push them
   upstream so the other device sees them too? Proposal: yes — after
   resolution, `git add <conflict_copy>` and push. Same net effect as
   Obsidian (the file appears in both vaults after subsequent sync).
3. **Naming collision**: if `<stem> (Conflicted copy <device> <ts>).<ext>`
   already exists (e.g., two conflicts in the same minute), append `-2`,
   `-3`, … before the extension. Not specified by Obsidian; we define it.

## Feasibility summary

- **Git → Obsidian-style conflict copies: realistic.** Git's index stages
  give us full access to `ours`, `theirs`, and `base` for every conflicted
  path. The algorithm is ~80 lines of Lua plus a naming helper, with no
  dependency beyond `git`, `vim.system`, and `vim.uv.fs_write`.
- **Binary files**: handled identically via `git show :N:path` piped bytes.
- **Non-trivial but bounded risks**: rename/rename conflicts and interrupted
  merges. Both should fall back to "abort merge + log + paused" rather than
  pretending success.
