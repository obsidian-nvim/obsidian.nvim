Docs for obsidian tags mostly applies: https://help.obsidian.md/tags

Tags are:

- case insensitive
- always displayed in lower case

## Searching tags

`:Obsidian tags [QUERY]` searches tags across the active workspace. With no
arguments, it uses the tag under the cursor when available; otherwise it opens a
tag picker.

The command accepts Obsidian-style tag search terms:

- `tag:#book` matches `book` and nested tags such as `book/child`.
- `tag:#book tag:#project` matches notes that contain both tags.
- `tag:#book OR tag:#movie` matches notes that contain either tag.
- `tag:#book -tag:#archive` excludes notes with `archive`.

Bare tags like `book` and `-archive` are treated as shorthand for `tag:#book`
and `-tag:#archive`.

Results always open as concrete tag locations with file, line, and column
context. Selecting tags from the picker builds an AND query by default.

TODO:

- option to disable inline tags
