See [LSP code actions](LSP.md#code-actions) for actions exposed via the LSP interface.

| name                 | mode     | description                            | arguments            |
| -------------------- | -------- | -------------------------------------- | -------------------- |
| `follow_link`        | `n`      | Open the link under the cursor.        | `link`               |
| `nav_link`           | `n`      | Navigate to next/previous link.        | `direction`          |
| `smart_action`       | `n`      | Context-aware action on the cursor.    |                      |
| `new`                | `n`      | Create a new note.                     | `id`                 |
| `new_from_template`  | `n`      | Create a new note from a template.     | `id`, `template`     |
| `unique_note`        | `n`      | Create a unique note.                  | `timestamp`          |
| `unique_link`        | `n`      | Create and insert a unique note link.  | `timestamp`          |
| `link_url`           | `n`      | Convert URL under cursor to link.      |                      |
| `paste`              | `n`      | Smart paste clipboard as markdown.     | `opts`               |
| `paste_url`          | `n`      | Interactively paste a URL.             | `url`, `opts`        |
| `add_property`       | `n`      | Add frontmatter property.              |                      |
| `insert_template`    | `n`      | Insert a template at cursor.           | `name`               |
| `rename`             | `n`      | Rename current note.                   | `name`               |
| `move_note`          | `n`      | Move current note to another folder.   |                      |
| `merge_note`         | `n`      | Merge current note into another note.  | `dst_note`           |
| `start_presentation` | `n`      | Start slide presentation.              | `buf`                |
| `workspace_symbol`   | `n`      | Search notes, aliases, and headings.   | `query`              |
| `insert_link`        | `n`      | Pick a note and insert its link.        | `query`              |
| `search_tags`        | `n`      | Search notes by tag.                   | `tags`               |
| `insert_tag`         | `n`      | Pick and insert a tag.                 |                      |
| `add_tag`            | `n`      | Pick and add tag to current note.       |                      |
| `toggle_checkbox`    | `n`, `v` | Toggle (cycle) checkbox state.         | `start_lnum`, `end_lnum` |
| `set_checkbox`       | `n`, `v` | Set to specific checkbox state.        | `state`              |
| `link`               | `v`      | Link selection to an existing note.    |                      |
| `link_new`           | `v`      | Create a new note and link selection.  | `title`              |
| `extract_note`       | `v`      | Move selection to a new note.          | `title`              |
