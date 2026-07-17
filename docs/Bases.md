# Bases

obsidian.nvim has an experimental, renderer-independent foundation for Obsidian
`.base` files. Opening a `.base` file inside a configured workspace attaches the
in-process LSP server and provides validation, document symbols, and a quick fix
for adding a missing table view.

The initial query layer supports common note and file properties, basic
expressions, filters, formulas, sorting, and limits. Table and list views can be
rendered as Markdown and previewed through embedded `.base` links.

## Public API

```lua
local bases = require "obsidian.base"

local document, diagnostics = bases.parse(source)
local view = bases.select_view(document, "Recent")
local filter = bases.effective_filter(document, view)
local property = bases.property.parse("label")
assert(property.canonical == "note.label")

bases.walk_filter(filter, function(node)
  -- Inspect filter_expression and filter_group nodes.
end)

local expression, expression_diagnostics = bases.expression.parse 'file.inFolder("Projects") && status != "done"'
```

Parsing is non-throwing for invalid user input. It returns a partial semantic
document where possible and reports structural or expression errors in the
diagnostics list.

Unknown top-level keys are retained in `document.config`. Unknown view keys are
retained in `view.config`. Bases view types are extensible, so an AST that drops
unknown configuration would prevent plugin-defined views from working.

## Model

There are two related models:

1. The Bases document model represents filters, formulas, property metadata,
   summaries, and views. It does not contain table rows or rendered cells.
2. The expression AST represents literals, identifiers, member access, indexed
   access, calls, unary operations, binary operations, and parentheses. Nodes
   carry byte offsets relative to the expression source.

Plain identifiers are normalized as note-property references. For example,
`label` and `note.label` retain different source AST shapes but both expose a
property reference whose `canonical` value is `note.label`. Identifiers in
function or method position are not treated as properties.

Global and view filters remain separate in the document. Use
`effective_filter()` to compose them with a synthetic `and` group. Keeping that
operation explicit prevents a query optimizer from accidentally changing the
meaning of nested `or` and `not` groups.

## Architecture

Future Bases support should keep the following pipeline:

```text
.base YAML
  -> lossless YAML document (source ownership and edits)
  -> semantic Bases document + expression ASTs
  -> evaluator and query plan
  -> view model (properties, groups, rows, values)
  -> renderer selected by view type
```

The current YAML parser produces values rather than a lossless concrete syntax
tree. That is enough for reading and validation. General property, filter, sort,
and view edits should wait for a YAML layer that preserves comments, quoting,
key order, and source ranges. The existing quick fix only appends a missing
`views` section and therefore does not rewrite existing YAML.

Query planning must also be separate from filter evaluation. For example,
extracting `file.inFolder()` as an unconditional cache constraint is incorrect
when that call occurs below an `or` or `not`. A planner may narrow candidates
only when the resulting constraint is implied by the complete filter AST.

## Rendering

Renderers consume a shared view model and register by view type. The built-in
renderers generate Markdown tables for table views and Markdown lists for list
views. Cards, maps, and plugin-defined views report that no renderer is installed
without changing parsing or query semantics.

Embed a Base in a Markdown note to show the rendered output as Neovim virtual
lines:

```markdown
![[Projects.base]]
![[Projects.base#List]]
```

The first form selects the first view. The second selects the view named `List`.
The original embed remains editable in the buffer and the generated output is
not written to the note.

Embedding is provided by the generic `obsidian.embed` subsystem. It also renders
whole Markdown notes, heading sections, and block references such as
`![[Note.md]]`, `![[Note.md#Heading]]`, and `![[Note.md#^block]]`. Providers can
be added with `require("obsidian.embed").register(provider)`.

The first query implementation intentionally leaves grouping, summaries, and
most Bases functions for later. Unsupported functions and view types are shown
as inline preview errors rather than being evaluated approximately.

The format and expression semantics follow Obsidian's
[Bases syntax](https://help.obsidian.md/bases/syntax) and
[Bases functions](https://help.obsidian.md/bases/functions) references.
