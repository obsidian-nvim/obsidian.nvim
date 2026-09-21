# YAOS CLI integration notes

Reviewed `kavinsood/yaos` branch `yaos3` at `be0b60db2872f438b7bd9fcb47671e22386c8788`.

## Current CLI contract

The unreleased CLI is in `packages/cli` and requires Node 24 or newer. Its current public commands are:

```text
YAOS_HOST=<https://server> YAOS_PAIRING_CODE=code yaos enroll <vaultPath>
yaos daemon <vaultPath>
```

Useful existing contracts:

- Pairing credentials are passed through the environment, not argv.
- State defaults to `${XDG_STATE_HOME:-~/.local/state}/yaos/headless/<vault-name>-<real-path-hash>/`.
- `YAOS_STATE_DIR` selects an explicit state leaf.
- A daemon prints `YAOS_DAEMON_READY <vaultId>` after initial convergence.
- Diagnostics go to stderr.
- `SIGINT` and `SIGTERM` initiate a graceful durable drain.
- Exit codes distinguish clean shutdown (`0`), retryable/configuration errors (`1`), fatal identity/protocol errors (`2`), and a held process lock (`17`).

## Missing integration surfaces

These are the main items to coordinate with the YAOS author.

### Required for a durable integration

1. **Version command**

   Add `yaos --version`. obsidian.nvim health checks and compatibility diagnostics should not have to infer the version from package files.

2. **Read-only JSON status command**

   Add a command such as:

   ```text
   yaos status <vaultPath> --json
   ```

   It should report CLI version, enrollment state, non-secret vault identity, state directory, and whether the lock appears held. It must never expose pairing codes or device tokens. Without this command, the MVP has to duplicate YAOS's state-path and enrollment-file format in Lua.

3. **Machine-readable daemon events**

   `YAOS_DAEMON_READY` is enough for initial startup, but it cannot drive an accurate statusline after subsequent local or remote changes. An opt-in JSONL protocol should report at least `starting`, `ready`, `syncing`, `settled`, `retrying`, and `fatal`, with a versioned event schema.

4. **Pending-enrollment reset**

   A failed enrollment persists its host and pairing code and rejects a different retry. An invalid or expired setup code therefore leaves the state directory wedged until users manually remove state. Add a safe reset command that only works before membership exists.

5. **Released install artifact**

   `packages/cli/package.json` currently has `private: true`, and the release workflow does not build or upload the CLI. Publish the npm package or attach a checksummed packed artifact to each compatible YAOS release.

### Desirable follow-ups

- A native one-shot `yaos sync <vaultPath>` command.
- A safe local `unenroll` command that refuses to discard pending durable work by default.
- Configurable exclude patterns and device name.
- A durable log destination or an explicit logging contract.
- Conventional successful exit for `--help`.
- A documented server/CLI compatibility matrix for schema, storage, and protocol versions.

## Implementation inconsistencies found

### Canvas watcher gap

The current engine contains Canvas hint handling, but `packages/cli/src/watcher.ts` ignores every non-`.md` file both in its ignore predicate and event recorder. Consequently `.canvas` changes cannot reach the Canvas hint path and are only discovered by periodic authoritative scans.

The headless end-to-end suite contains no Canvas scenarios, so this behavior is not currently caught there.

### Stale CLI documentation

`packages/cli/README.md` says that the CLI synchronizes `.md` files only. Newer architecture and implementation files claim support for closed semantic Canvas files. The supported contract needs to be reconciled after the watcher behavior is fixed and tested.

### No ongoing status contract

The daemon emits one readiness line but no stable ongoing convergence events. stderr is human-oriented and cannot safely be interpreted as a versioned API.

### Supervisor expectation

Exit code `1` denotes a retryable runtime failure, but the CLI exits and provides no supervisor. A production Neovim backend must implement bounded restart/backoff or YAOS must absorb retryable startup failures itself.

## Local verification

At the reviewed commit:

- CLI TypeScript typecheck passed.
- CLI bundle build passed.
- Isolated bundle smoke test passed.
- Packed-install/bin smoke test passed.
- The complete YAOS headless suite could not be run in this environment because installation of the Wrangler dependency failed due npm registry/cache network failures.

For this repository's MVP, a source checkout and built executable are available at:

```text
deps/yaos/packages/cli/dist/yaos.mjs
```

`deps/` is ignored and this build is intentionally only a local test dependency.
