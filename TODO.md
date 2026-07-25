# TODO

## Attachment completion follow-ups

- Add a ripgrep-backed attachment search path for users who keep `cache.enabled = false`.
  Keep the completion source on `attachment.find_async()` so backend selection remains outside the LSP handler.
- Add cache query indexes if profiling shows that filtering all cached attachments per completion request is significant in very large vaults.
- Decide whether user-configurable attachment extensions should supplement the built-in image, audio, video, canvas, and PDF types.
- Reuse cached attachments and note `links_out` for orphan-attachment and broken-link diagnostics tracked in issue #792.
- Add multi-instance cache coordination so concurrent Neovim processes cannot overwrite newer cache state.
