Docs for obsidian tags mostly applies: https://help.obsidian.md/tags

Tags are:

- case insensitive
- always displayed in lower case

## Searching tags

`:Obsidian tags [TAG ...]` searches tags across the active workspace. With no
arguments, it uses the tag under the cursor when available; otherwise it opens a
tag picker.

The command supports a small query syntax:

- `tag` matches `tag` and nested tags such as `tag/child`.
- `tag1 tag2` matches notes that contain either tag.
- `+tag1 tag2` matches only notes that contain all tags. A single `+` prefix on
  any tag enables AND mode for the whole query.
- `#tag` restricts results to inline `#tag` occurrences outside YAML
  frontmatter and opens the picker at the matching line and column.
- `+#tag1 tag2` combines AND mode with inline-only matching.

Single-tag and hash-prefixed searches list tag locations. Multi-tag searches
without `#` list matching notes and show which query tags matched each note.

TODO:

- option to disable inline tags
