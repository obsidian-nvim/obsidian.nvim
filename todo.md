# feat/add_attachment — PR Review TODO

## Design issues

- [ ] `lua/obsidian/attachment.lua:126` — `vim.system():wait()` blocks Neovim UI during curl download. Use async `vim.system(cmd, opts, on_exit)`.
- [ ] No overwrite protection — `fs_copyfile` and `curl -o` silently overwrite existing files. Check + prompt or auto-rename.

## Minor

- [ ] `attachment.lua:166` — param named `dst` but receives source path. Rename.
- [ ] `format_link` returns `nil` if `style` not recognized (no else branch).
