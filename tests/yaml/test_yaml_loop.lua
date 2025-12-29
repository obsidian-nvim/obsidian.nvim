local yaml = require "obsidian.yaml"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

---@param str string
local function loop_parse(str)
  local parsed = yaml.loads(str)
  local dumped = yaml.dumps(parsed)
  eq(str, dumped)
end

T["null"] = function()
  loop_parse "null"
end

T["should dump numbers"] = function()
  loop_parse "1"
end

T["should dump strings"] = function()
  loop_parse "hi there"
  loop_parse "hi it's me"
  loop_parse [[foo: bar]]
end

T["should dump table with string values"] = function()
  loop_parse [[foo: bar]]
end

T["should dump arrays with string values"] = function()
  loop_parse "- foo\n- bar"
end

T["should dump arrays with number values"] = function()
  loop_parse "- 1\n- 2"
end

T["should dump arrays with simple table values"] = function()
  loop_parse "- a: 1\n- b: 2"
end

T["should dump tables with string values"] = function()
  loop_parse "a: foo\nb: bar"
end

T["should dump tables with number values"] = function()
  loop_parse "a: 1\nb: 2"
end

T["should dump tables with array values"] = function()
  loop_parse "a:\n  - foo\nb:\n  - bar"
end

T["should dump tables with empty array"] = function()
  loop_parse "a: []"
end

T["should quote empty strings or strings with just whitespace"] = function()
  loop_parse 'a: ""'
  loop_parse 'a: " "'
end

T["should not quote date-like strings"] = function()
  loop_parse "a: 2025.5.6"
  loop_parse "a: 2023_11_10 13:26"
end

T["should otherwise quote strings with a colon followed by whitespace"] = function()
  loop_parse [[a: "2023: a letter"]]
end

T["should quote strings that start with special characters"] = function()
  loop_parse [[a: "& aaa"]]
  loop_parse [[a: "! aaa"]]
  loop_parse [[a: "- aaa"]]
  loop_parse [[a: "{ aaa"]]
  loop_parse [[a: "[ aaa"]]
  loop_parse [[a: "'aaa'"]]
  loop_parse [[a: "\"aaa\""]]
end

T["should not unnecessarily escape double quotes in strings"] = function()
  loop_parse 'a: his name is "Winny the Poo"'
end

return T
