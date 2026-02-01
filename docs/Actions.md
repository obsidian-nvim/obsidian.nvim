See [LSP code actions](LSP.md#code-actions) for actions exposed via the LSP interface.

| name                | mode     | description                               | arguments |
| ------------------- | -------- | ----------------------------------------- | --------- |
| `follow_link`       | `n`      | Open the link under the cursor.           |           |
| `nav_link`          | `n`      | Navigate through link history.            |           |
| `smart_action`      | `n`      | Context-aware action on the cursor.       |           |
| `new_from_template` | `n`      | Create a new note from a template.        |           |
| `add_property`      | `n`      | Add frontmatter property.                 |           |
| `insert_template`   | `n`      | Insert a template at cursor.              | `name`    |
| `rename`            | `n`      | Rename current note.                      | `name`    |
| `toggle_checkbox`   | `n`, `v` | Toggle checkbox state.                    |           |
| `set_checkbox`      | `n`, `v` | Set checkbox state.                       | `state`   |
| `link`              | `v`      | Link selection to an existing note.       |           |
| `link_new`          | `v`      | Create a new note and link selection.     | `title`   |
| `extract_note`      | `v`      | Move selection to a new note and link it. | `title`   |
