# TODO

## High Priority

### Race condition in `sync_once`
- **File**: `lua/obsidian/sync/backends/git.lua`
- **Issue**: If an unexpected error occurs during `sync_once`, the `in_flight[dir]` flag is never cleared, blocking future syncs.
- **Fix**: Use `pcall` or `finally`-style pattern to ensure `in_flight[dir]` is cleared on all exit paths.

### Debounce timer cleanup
- **File**: `lua/obsidian/sync/init.lua`
- **Issue**: Debounce timers are not properly cleaned up when:
  - Timer callback is executing (stopping/closing inside callback is risky)
  - Workspace is switched
  - Plugin is unloaded
- **Fix**: Add cleanup function for debounce timers, hook into workspace switch and `VimLeavePre` events.

### Silent mode logic bug
- **File**: `lua/obsidian/sync/init.lua:87`
- **Issue**: `if ok or ok == nil` treats `nil` as success. Obsidian backend's `pause()` can return `nil`, triggering false "Paused sync" messages.
- **Fix**: Change condition to explicit `if ok then` check.

## Medium Priority

### Missing design doc features
- **Retry loop for push failures**: Implement retry with cap at 3 attempts and exponential backoff before aborting.
- **Delete/modify conflict handling**: Handle cases where one side deletes a file and the other modifies it.
- **Binary file conflict handling**: Use `git show` with raw byte output, write via `vim.uv.fs_write` without text encoding.
- **Sync status edge cases**: Ensure proper `syncing → synced`/`paused` transitions in all error cases.

### Health check improvements
- **File**: `lua/obsidian/health.lua`
- **Issue**: Git backend health check only verifies `git` executable, not repo initialization or remote configuration.

## Low Priority

### Conflict copy naming collision
- **File**: `lua/obsidian/sync/backends/git.lua`
- **Issue**: Conflict copy naming doesn't handle existing files with same name (per design doc open questions).
- **Note**: Partial implementation exists, needs testing for edge cases.
