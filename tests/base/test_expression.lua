local expression = require "obsidian.base.expression"

local eq = MiniTest.expect.equality
local T = MiniTest.new_set()

T["parses member calls without renderer-specific nodes"] = function()
  local ast, diagnostics = expression.parse 'file.hasTag("book")'

  eq(0, #diagnostics)
  eq("call", ast.kind)
  eq("member", ast.callee.kind)
  eq("identifier", ast.callee.object.kind)
  eq("file", ast.callee.object.name)
  eq("hasTag", ast.callee.property)
  eq("book", ast.arguments[1].value)
end

T["normalizes plain identifiers as note property shorthand"] = function()
  local ast, diagnostics = expression.parse "label == note.label"

  eq(0, #diagnostics)
  eq("identifier", ast.left.kind)
  eq("note", ast.left.reference.namespace)
  eq("label", ast.left.reference.name)
  eq("note.label", ast.left.reference.canonical)
  eq(false, ast.left.reference.explicit)
  eq("member", ast.right.kind)
  eq("note.label", ast.right.reference.canonical)
  eq(true, ast.right.reference.explicit)
end

T["does not treat global functions or methods as properties"] = function()
  local ast, diagnostics = expression.parse 'if(label.contains("x"), label, file.name)'

  eq(0, #diagnostics)
  eq(nil, ast.callee.reference)
  eq(nil, ast.arguments[1].callee.reference)
  eq("note.label", ast.arguments[1].callee.object.reference.canonical)
  eq("note.label", ast.arguments[2].reference.canonical)
  eq("file.name", ast.arguments[3].reference.canonical)
end

T["observes arithmetic, comparison, and boolean precedence"] = function()
  local ast, diagnostics = expression.parse "price + tax * 2 >= 10 && !done"

  eq(0, #diagnostics)
  eq("&&", ast.operator)
  eq(">=", ast.left.operator)
  eq("+", ast.left.left.operator)
  eq("*", ast.left.left.right.operator)
  eq("unary", ast.right.kind)
  eq("!", ast.right.operator)
end

T["parses chained calls and indexed note properties"] = function()
  local ast, diagnostics = expression.parse 'note["release date"].format("YYYY-MM-DD").contains("2026")'

  eq(0, #diagnostics)
  eq("call", ast.kind)
  eq("contains", ast.callee.property)
  eq("call", ast.callee.object.kind)
  eq("format", ast.callee.object.callee.property)
  eq("index", ast.callee.object.callee.object.kind)
  eq("release date", ast.callee.object.callee.object.index.value)
end

T["retains source offsets"] = function()
  local ast = expression.parse "  file.name == 'A'"

  eq({ start = 2, finish = 18 }, ast.range)
  eq({ start = 15, finish = 18 }, ast.right.range)
end

T["returns diagnostics for incomplete expressions"] = function()
  local _, diagnostics = expression.parse "file.name =="

  eq(true, #diagnostics > 0)
  eq("expression.expected-expression", diagnostics[1].code)
end

return T
