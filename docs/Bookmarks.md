Reads bookmarks from `.obsidian/bookmarks.json` in current workspace and lets you pick one via `vim.ui.select`.

See: <https://help.obsidian.md/bookmarks>

## Supported types

| Type     | Behavior on select                                        |
| -------- | --------------------------------------------------------- |
| `file`   | Opens note, jumps to block/heading subpath                |
| `folder` | Opens via `vim.cmd.edit`                                  |
| `url`    | Opens via `vim.ui.open`                                   |
| `search` | Evaluates the stored Obsidian query and shows its matches |
| `group`  | Recurses into nested bookmark list                        |

## Caveats

- No `graph` type — Obsidian app does not bookmark graph views.
- Editing bookmarks is not implemented. Bookmarks can be added from code actions and note pickers, moved into groups from the bookmark picker, or removed through the Lua API.
