Reads bookmarks from `.obsidian/bookmarks.json` in current workspace and lets you pick one via `vim.ui.select`.

See: <https://help.obsidian.md/bookmarks>

## Supported types

| Type     | Behavior on select                          |
| -------- | ------------------------------------------- |
| `file`   | Opens note, jumps to block/heading subpath  |
| `folder` | Opens via `vim.cmd.edit`                    |
| `url`    | Opens via `vim.ui.open`                     |
| `search` | Runs `picker.grep` with stored query string |
| `group`  | Recurses into nested bookmark list          |

## Caveats

- No `graph` type — Obsidian app does not bookmark graph views.
- `search` type is partial — passes raw query to grep. Proper Obsidian search-term parser pending: https://github.com/obsidian-nvim/obsidian.nvim/issues/542
- Adding / editing / removing bookmarks not implemented. Read-only for now — manage them in Obsidian app.
