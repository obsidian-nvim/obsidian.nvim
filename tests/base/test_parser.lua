local base = require "obsidian.base"

local eq = MiniTest.expect.equality
local T = MiniTest.new_set()

local source = [=[
filters:
  and:
    - file.hasTag("media")
formulas:
  age: "(now() - file.ctime) / 1000"
properties:
  formula.age:
    displayName: Age
summaries:
  customAverage: values.mean().round(3)
views:
  - type: table
    name: Recent
    filters:
      and:
        - status != "done"
    order:
      - file.name
      - formula.age
    sort:
      - property: formula.age
        direction: DESC
    groupBy:
      property: status
      direction: ASC
    summaries:
      formula.age: Average
    columnSize:
      file.name: 120
  - type: map
    name: Places
    coordinates: note.coordinates
pluginOption: preserved
]=]

T["parses the complete renderer-neutral document shape"] = function()
  local document, diagnostics = base.parse(source)

  eq(0, #diagnostics)
  eq("base", document.kind)
  eq("filter_group", document.filters.kind)
  eq("binary", document.formulas.age.expression.kind)
  eq("call", document.summaries.customAverage.expression.kind)
  eq("Age", document.properties["formula.age"].displayName)
  eq(2, #document.views)
  eq("table", document.views[1].type)
  eq("status", document.views[1].group_by.property)
  eq(120, document.views[1].config.columnSize["file.name"])
  eq("note.coordinates", document.views[2].config.coordinates)
  eq("preserved", document.config.pluginOption)
end

T["combines global and view filters without flattening their logic"] = function()
  local document = base.parse(source)
  local effective = base.effective_filter(document, document.views[1])

  eq("filter_group", effective.kind)
  eq("and", effective.operator)
  eq(true, effective.synthetic)
  eq(document.filters, effective.children[1])
  eq(document.views[1].filters, effective.children[2])
end

T["walks nested filter groups"] = function()
  local document = base.parse(source)
  local kinds = {}
  base.walk_filter(document.filters, function(node)
    kinds[#kinds + 1] = node.kind
  end)

  eq({ "filter_group", "filter_expression" }, kinds)
end

T["selects the first or named view"] = function()
  local document = base.parse(source)

  eq("Recent", base.select_view(document).name)
  eq("Places", base.select_view(document, "Places").name)
  eq(nil, base.select_view(document, "Missing"))
end

T["normalizes plain view properties to the note namespace"] = function()
  local document = base.parse(source)

  eq("note.status", base.property.parse(document.views[1].group_by.property).canonical)
  eq("formula.age", base.property.parse(document.views[1].order[2]).canonical)
end

T["reports structural validation errors without throwing"] = function()
  local document, diagnostics = base.parse "formulas:\n  bad: 10"

  eq("base", document.kind)
  eq("base.missing-views", diagnostics[1].code)
  eq("base.invalid-formula", diagnostics[2].code)
end

T["preserves empty formula placeholders without an expression error"] = function()
  local document, diagnostics = base.parse [[formulas:
  Untitled: ""
views:
  - type: table
    name: Table]]

  eq(0, #diagnostics)
  eq("", document.formulas.Untitled.source)
  eq(nil, document.formulas.Untitled.expression)
end

T["reports YAML failures with a source line"] = function()
  local document, diagnostics = base.parse "views:\n  - type: table\n name: broken"

  eq(nil, document)
  eq("base.invalid-yaml", diagnostics[1].code)
  eq(2, diagnostics[1].line)
end

return T
