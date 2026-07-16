---@alias obsidian.base.DiagnosticSeverity "error"|"warning"

---@class obsidian.base.SourceRange
---@field start integer 0-based byte offset, inclusive.
---@field finish integer 0-based byte offset, exclusive.

---@class obsidian.base.Diagnostic
---@field code string
---@field message string
---@field severity obsidian.base.DiagnosticSeverity
---@field path? string Location in the semantic Bases document.
---@field range? obsidian.base.SourceRange Location in an expression source string.
---@field line? integer 0-based line in the `.base` source.

---@class obsidian.base.ExpressionBase
---@field kind string
---@field range obsidian.base.SourceRange
---@field reference? obsidian.base.PropertyReference

---@class obsidian.base.LiteralExpression : obsidian.base.ExpressionBase
---@field kind "literal"
---@field value any
---@field raw string

---@class obsidian.base.IdentifierExpression : obsidian.base.ExpressionBase
---@field kind "identifier"
---@field name string
---@field reference? obsidian.base.PropertyReference

---@class obsidian.base.MemberExpression : obsidian.base.ExpressionBase
---@field kind "member"
---@field object obsidian.base.Expression
---@field property string
---@field reference? obsidian.base.PropertyReference

---@class obsidian.base.IndexExpression : obsidian.base.ExpressionBase
---@field kind "index"
---@field object obsidian.base.Expression
---@field index obsidian.base.Expression
---@field reference? obsidian.base.PropertyReference

---@class obsidian.base.PropertyReference
---@field namespace "note"|"file"|"formula"
---@field name string
---@field source string Original property spelling.
---@field canonical string Fully qualified property name.
---@field explicit boolean Whether the source included a namespace.

---@class obsidian.base.CallExpression : obsidian.base.ExpressionBase
---@field kind "call"
---@field callee obsidian.base.Expression
---@field arguments obsidian.base.Expression[]

---@class obsidian.base.UnaryExpression : obsidian.base.ExpressionBase
---@field kind "unary"
---@field operator string
---@field operand obsidian.base.Expression

---@class obsidian.base.BinaryExpression : obsidian.base.ExpressionBase
---@field kind "binary"
---@field operator string
---@field left obsidian.base.Expression
---@field right obsidian.base.Expression

---@class obsidian.base.GroupExpression : obsidian.base.ExpressionBase
---@field kind "group"
---@field expression obsidian.base.Expression

---@alias obsidian.base.Expression obsidian.base.LiteralExpression|obsidian.base.IdentifierExpression|obsidian.base.MemberExpression|obsidian.base.IndexExpression|obsidian.base.CallExpression|obsidian.base.UnaryExpression|obsidian.base.BinaryExpression|obsidian.base.GroupExpression

---@class obsidian.base.FilterExpression
---@field kind "filter_expression"
---@field source string
---@field expression obsidian.base.Expression?

---@class obsidian.base.FilterGroup
---@field kind "filter_group"
---@field operator "and"|"or"|"not"
---@field children obsidian.base.Filter[]
---@field synthetic? boolean

---@alias obsidian.base.Filter obsidian.base.FilterExpression|obsidian.base.FilterGroup

---@class obsidian.base.ExpressionDeclaration
---@field kind "formula"|"summary"
---@field name string
---@field source string
---@field expression obsidian.base.Expression?

---@class obsidian.base.View
---@field kind "view"
---@field type string?
---@field name string?
---@field filters obsidian.base.Filter?
---@field order string[]
---@field sort table[]
---@field group_by table?
---@field summaries table<string, string>
---@field limit number?
---@field config table<string, any> View-specific and plugin-defined keys.
---@field raw table<string, any>

---@class obsidian.base.Document
---@field kind "base"
---@field source string
---@field filters obsidian.base.Filter?
---@field formulas table<string, obsidian.base.ExpressionDeclaration>
---@field properties table<string, any>
---@field summaries table<string, obsidian.base.ExpressionDeclaration>
---@field views obsidian.base.View[]
---@field config table<string, any> Unknown top-level keys, preserved for extensions.
---@field raw table<string, any>

return {}
