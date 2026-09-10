# Obsidian URI

obsidian.nvim handles [`obsidian://` URIs](https://obsidian.md/help/uri) inside Neovim. A URI can open a note, create or update a note, open a daily note, create a unique note, search a workspace, or select a workspace.

To open `obsidian://` links from a browser or another application, see [[Obsidian-URI-Registration]].

## Configuration

```lua
require("obsidian").setup {
  uri = {
    -- Handle obsidian:// links followed inside Neovim.
    enabled = true,

    -- Ask before a followed link creates or changes a file.
    -- Direct Lua calls and links received from the OS are not prompted.
    require_confirmation = true,
  },
}
```

When `uri.enabled` is false, followed `obsidian://` links use the normal external-link flow from the `open` configuration.

The confirmation applies to `new`, `daily`, `unique`, and `open` with `append` or `prepend`.

## Compatibility

| Action | Support | Notes |
| --- | --- | --- |
| `open` | Supported | Opens configured workspaces and existing files; heading and block navigation work. |
| `new` | Supported | Supports `name`, `file`, `path`, content, clipboard, mutation flags, `silent`, `paneType`, and callbacks. |
| `daily` | Supported | Uses obsidian.nvim daily-note settings and accepts content, mutation, opening, and callback parameters. |
| `unique` | Supported | Uses the configured unique-note folder, format, template, and collision handling. |
| `search` | Approximation | Opens the obsidian.nvim grep picker. Obsidian search operators are not translated. |
| `choose-vault` | Approximation | Opens the configured workspace picker rather than Obsidian's vault manager. |
| `hook-get-address` | Partial | Works when the current Neovim buffer is a note. A fresh launcher process has no focused note. |

### Known differences

- Vault IDs such as `ef6ca3e3b524d22f` are not available to obsidian.nvim. Use a configured workspace name or the vault root directory name.
- `paneType=window` has no Neovim equivalent. obsidian.nvim warns and uses `open_notes_in`.
- `paneType=split` opens a horizontal split.
- `append` and `prepend` preserve existing frontmatter, but obsidian.nvim does not merge properties supplied in the new content.
- Absolute `path` values must belong to a configured workspace. obsidian.nvim will not open or write arbitrary paths outside configured workspaces.

## URI format and encoding

The standard form is:

```text
obsidian://action?param1=value&param2=value
```

Encode each parameter value. Spaces become `%20`, `/` inside a parameter becomes `%2F`, `#` becomes `%23`, and `^` becomes `%5E`.

```text
obsidian://open?vault=My%20Vault&file=Projects%2FRoadmap%23Next%20steps
```

The parser also accepts Obsidian's shorthand forms:

```text
obsidian://My%20Vault/Projects/Roadmap
obsidian:///absolute/path/to/vault/Projects/Roadmap
```

Do not decode the complete URI before passing it to `handle()`. Decoding `%26` into `&`, for example, changes content into a second query parameter.

## Workspace and target resolution

For `vault=...`, obsidian.nvim checks:

1. Configured workspace name.
2. Vault root directory name.

For `path=...`, obsidian.nvim selects the most specific configured workspace containing that path. `path` overrides both `vault` and `file`, matching Obsidian's URI rules.

A relative `file` starts at the selected vault root. obsidian.nvim resolves symlinks and rejects `..` traversal outside that root.

## Open

```text
obsidian://open?vault=Notes&file=Projects%2FRoadmap
obsidian://open?vault=Notes&file=Projects%2FRoadmap%23Heading
obsidian://open?vault=Notes&file=Projects%2FRoadmap%23%5Eblock-id
obsidian://open?path=%2Fhome%2Fuser%2FNotes%2FProjects%2FRoadmap.md
```

Parameters:

| Parameter | Behavior |
| --- | --- |
| `vault` | Select a configured workspace by name or vault root name. |
| `file` | Open a path relative to the vault root. `.md` may be omitted. |
| `path` | Open an absolute path and select its containing workspace. |
| `paneType=tab` | Open a new Neovim tab. |
| `paneType=split` | Open a horizontal split. |
| `paneType=window` | Warn and use the configured open strategy. |
| `content` / `clipboard` | Content source for `append` or `prepend`. |
| `append` / `prepend` | Add content to the existing note body. |

If a heading or block does not exist, obsidian.nvim warns and still opens the note.

## Create a note

```text
obsidian://new?vault=Notes&name=Inbox
obsidian://new?vault=Notes&file=Clippings%2FPage%20title&content=Saved%20text
obsidian://new?vault=Notes&file=Journal%2FLog&content=Entry&append&silent
```

Target precedence follows Obsidian:

1. `path`, an absolute path in a configured workspace.
2. `file`, relative to the vault root.
3. `name`, resolved through the configured new-note location and `note_path_func`.
4. A generated ID when no target is supplied.

`name` skips `note_id_func`, so the requested name stays intact. `file` and `path` address exact paths.

### Content and existing files

- `clipboard` uses Neovim's `+` register. If that register is empty, obsidian.nvim uses `content` as a fallback.
- A new note with content contains that content without adding the default obsidian.nvim template or frontmatter.
- A new note without content uses the configured note template and frontmatter behavior.
- An existing note remains unchanged unless `append`, `prepend`, or `overwrite` is present.
- `append` takes precedence over `prepend` and `overwrite` when flags conflict.
- `silent` writes the note without opening it.

## Daily note

```text
obsidian://daily?vault=Notes
obsidian://daily?vault=Notes&content=Daily%20entry&append&silent
```

The handler uses `daily_notes.folder`, date format, tags, and template. It writes a missing daily note before opening it. Content mutation follows the `new` rules, while a newly created daily note keeps its configured daily template.

## Unique note

```text
obsidian://unique?vault=Notes
obsidian://unique?vault=Notes&content=Idea
```

The handler uses the unique-note API, including the configured folder, timestamp format, template, and collision handling. Supplied content follows the generated note's template content.

`unique` does not support `silent`.

## Search and workspace selection

```text
obsidian://search?vault=Notes
obsidian://search?vault=Notes&query=release%20notes
obsidian://choose-vault
```

`search` opens the configured grep picker with `query` as its initial input. `choose-vault` lists configured workspaces and excludes the internal documentation workspace.

Both actions need an interactive Neovim instance.

## Hook and callbacks

```text
obsidian://hook-get-address
obsidian://hook-get-address?x-success=hook%3A%2F%2Fcallback
```

Without `x-success`, `hook-get-address` copies a Markdown link for the current note to the `+` register. With `x-success`, obsidian.nvim opens the callback URI with these encoded parameters:

- `name`: filename without its extension.
- `url`: an `obsidian://open` URI for the note.
- `file`: a `file://` URI for the note.

Supported note-creation handlers also send these fields to `x-success`. On failure, `x-error` receives `errorMessage`.

The bundled OS launcher starts a new Neovim process, so it cannot know which note another Neovim process has focused. Call `hook-get-address` inside the active instance.

## Lua API

```lua
local result = require("obsidian.uri").handle(
  "obsidian://new?vault=Notes&name=Inbox&silent"
)

if not result.ok then
  vim.notify(result.error, vim.log.levels.ERROR)
end
```

`handle()` returns an `obsidian.uri.Result`:

```lua
---@class obsidian.uri.Result
---@field ok boolean
---@field action string
---@field interactive boolean
---@field silent boolean
---@field error string?
---@field note obsidian.Note?
---@field data table?
```

You can parse without dispatching:

```lua
local parsed = require("obsidian.uri").parse(uri)
if parsed and require("obsidian.uri").is_mutating(parsed) then
  -- Apply an application-specific policy.
end
```
