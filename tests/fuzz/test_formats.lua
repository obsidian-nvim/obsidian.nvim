local Fuzz = dofile "tests/fuzz/helpers.lua"
local Frontmatter = require "obsidian.frontmatter"
local Path = require "obsidian.path"
local link = require "obsidian.link.parser"
local uri = require "obsidian.uri"
local yaml = require "obsidian.yaml"
local Parser = require "obsidian.yaml.parser"

local T = MiniTest.new_set()

local function check_elements(lines, elements, base_row, expected)
  for _, element in ipairs(elements) do
    assert(element.kind == "scalar", "unexpected element kind")
    local value = expected
    for _, part in ipairs(element.path) do
      assert(type(value) == "table", "path enters a non-table value")
      value = value[part]
    end
    assert(value == element.value, "element path disagrees with parsed value")
    local range = element.range
    assert(range.start_row >= base_row and range.end_row < base_row + #lines, "element row outside YAML")
    assert(range.start_row < range.end_row or range.start_col <= range.end_col, "reversed scalar range")
    for _, endpoint in ipairs {
      { range.start_row, range.start_col },
      { range.end_row, range.end_col },
    } do
      local row, col = endpoint[1], endpoint[2]
      assert(col >= 0 and col <= #lines[row - base_row + 1], "element column outside YAML")
    end
  end
end

T["YAML dump/load preserves generated metadata and source ranges"] = function()
  Fuzz.run("yaml-roundtrip", 404, function(rng)
    return rng:yaml_document()
  end, function(value)
    local lines = yaml.dumps_lines(value)
    local before = vim.deepcopy(lines)
    local decoded, _, elements = yaml.loads(lines, { base_row = 7 })
    assert(vim.deep_equal(decoded, value), "YAML round trip changed metadata")
    assert(vim.deep_equal(lines, before), "parser mutated its input")
    check_elements(lines, elements, 7, decoded)
    local from_text = yaml.loads(table.concat(lines, "\n"))
    assert(vim.deep_equal(from_text, value), "string and line inputs disagree")
  end)
end

T["frontmatter dump and validation preserve safe metadata"] = function()
  Fuzz.run("frontmatter", 909, function(rng)
    local data = rng:yaml_document()
    data.id = rng:pick { "note", "2026", "hello world", "é你好" }
    data.aliases = { rng:yaml_value(), rng:yaml_value() }
    return data
  end, function(data)
    local dumped = Frontmatter.dump(data)
    assert(dumped[1] == "---" and dumped[#dumped] == "---", "missing frontmatter boundaries")
    local body = vim.list_slice(dumped, 2, #dumped - 1)
    local info, metadata, errors, elements = Frontmatter.parse(body, "note.md", { base_row = 7 })
    assert(#errors == 0, "valid frontmatter produced validation errors")
    assert(info.id == data.id and vim.deep_equal(info.tags, data.tags), "validated fields changed")
    assert(vim.deep_equal(info.aliases, data.aliases), "aliases changed")
    assert(vim.deep_equal(metadata, { title = data.title, meta = data.meta, count = data.count }), "metadata changed")
    check_elements(body, elements, 7, data)
  end)
end

T["YAML parser recovers after malformed input"] = function()
  Fuzz.run("yaml-recovery", 505, function(rng)
    local lines = rng:document()
    -- Mix Markdown and malformed YAML; syntax errors are expected for this input.
    lines[1] = rng:pick { "tags: [", "key: {broken", "a: 1", "- [x, y", "title: 'unfinished" }
    return lines
  end, function(lines)
    local parser = Parser.new()
    local ok, value, _, elements = pcall(parser.parse, parser, lines, { base_row = 3 })
    if ok then
      check_elements(lines, elements, 3, value)
    else
      assert(type(value) == "string", "parse error must have a message")
    end
    local decoded, _, next_elements = parser:parse({ "title: good" }, { base_row = 11 })
    assert(decoded.title == "good" and #next_elements == 1, "parser did not recover")
    assert(next_elements[1].range.start_row == 11, "parser retained a previous source row")
  end)
end

-- Encode every reserved/non-ASCII byte so the URI oracle does not depend on
-- the plugin's encoder (which has different rules for some URL characters).
local function encode(value)
  return (value:gsub("([^%w%-._~])", function(byte)
    return ("%%%02X"):format(byte:byte())
  end))
end

T["URI query fields and fragments survive percent encoding"] = function()
  Fuzz.run("uri-fields", 606, function(rng)
    local segment = { "a+b", "100%", "x&y", "a=b", "hello world", "é你好", "note" }
    return {
      vault = rng:pick(segment),
      file = rng:pick(segment) .. "/" .. rng:pick(segment),
      content = rng:pick(segment) .. " # " .. rng:pick(segment),
      anchor = rng:pick { "#Heading", "#^block-id", "#C# notes" },
    }
  end, function(input)
    local target = "obsidian://open?vault="
      .. encode(input.vault)
      .. "&file="
      .. encode(input.file .. ".md" .. input.anchor)
      .. "&content="
      .. encode(input.content)
      .. "&silent"
    local parsed = assert(uri.parse(target), "valid obsidian URI did not parse")
    assert(parsed.action == "open" and parsed.vault == input.vault, "vault changed")
    assert(parsed.file == input.file and parsed.anchor == input.anchor, "file or anchor changed")
    assert(parsed.content == input.content and parsed.silent, "query content or flag changed")
    local shorthand = assert(uri.parse("obsidian://" .. encode(input.vault) .. "/" .. encode(input.file)))
    assert(shorthand.action == "open" and shorthand.vault == input.vault, "shorthand vault changed")
    assert(shorthand.file == input.file, "shorthand file changed")
  end)
end

T["URI parser accepts bounded user-supplied query text"] = function()
  Fuzz.run("uri-arbitrary", 1010, function(rng)
    return "obsidian://open?vault=" .. rng:line() .. "&file=" .. rng:line()
  end, function(target)
    local parsed = uri.parse(target)
    assert(parsed and parsed.action == "open" and type(parsed.params) == "table", "URI parse result is invalid")
  end)
end

T["link destinations round trip within the non-URI domain"] = function()
  Fuzz.run("link-fragments", 707, function(rng)
    return {
      location = rng:pick { "", "note", "folder/a b", "C:\\vault\\note", "é/你好", "100%" },
      fragment = rng:pick { "none", "anchor", "block" },
      name = rng:pick { "Heading", "two words", "é你好", "block-id" },
    }
  end, function(input)
    local anchor = input.fragment == "anchor" and input.name or nil
    local block = input.fragment == "block" and input.name or nil
    local location, found_anchor, found_block = link.parse(link.format(input.location, anchor, block))
    assert(location == input.location and found_anchor == anchor and found_block == block, "link round trip changed")
    local external = "https://example.com/page#" .. input.name
    local uri_location, uri_anchor, uri_block = link.parse(external)
    assert(uri_location == external and uri_anchor == nil and uri_block == nil, "URI fragment was split")
  end)
end

T["joined vault paths can be made relative to their parent"] = function()
  Fuzz.run("path-relative", 808, function(rng)
    local segments = { "notes", "folder with spaces", "é你好", "a-b", "100%" }
    return { dir = rng:pick(segments), name = rng:pick(segments) .. ".md" }
  end, function(input)
    local parent = Path.new "vault" / input.dir
    local file = parent / input.name
    assert(file:parent() == parent, "joining changed the parent")
    assert(file:relative_to(parent).filename == input.name, "relative path changed the filename")
  end)
end

return T
