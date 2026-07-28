local M = require "obsidian.search.ripgrep"

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

-- https://github.com/BurntSushi/ripgrep/blob/master/GUIDE.md#manual-filtering-globs
T["escape_rg_glob: leaves normal text unchanged"] = function()
  eq(M._escape_rg_glob "hello-world_123", "hello-world_123")
end

T["escape_rg_glob: escapes braces (alternation)"] = function()
  eq(M._escape_rg_glob "{foo}", "[{]foo[}]")
end

T["escape_rg_glob: escapes wildcards"] = function()
  eq(M._escape_rg_glob "*a?b*", "[*]a[?]b[*]")
end

T["escape_rg_glob: escapes character classes"] = function()
  eq(M._escape_rg_glob "[ab]", "[[]ab[]]")
end

T["escape_rg_glob: escapes closing bracket correctly"] = function()
  eq(M._escape_rg_glob "]", "[]]")
end

T["escape_rg_glob: escapes backslash"] = function()
  eq(M._escape_rg_glob [[a\b\c]], [[a[\]b[\]c]])
end

T["escape_rg_glob: realistic URL-like input stays literal"] = function()
  local input = "https://example.com/{foo}[bar]?a=1*b"
  local expected = "https://example.com/[{]foo[}][[]bar[]][?]a=1[*]b"
  eq(M._escape_rg_glob(input), expected)
end

T["escape_rg_glob: roundtrip-ish: embed in *...* glob safely"] = function()
  local input = "*{sdsds*.md"
  local glob = "*" .. M._escape_rg_glob(input) .. "*"
  local expected = "*[*][{]sdsds[*].md*"
  eq(glob, expected)
end

return T
