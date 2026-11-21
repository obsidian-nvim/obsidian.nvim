-- Deterministic generators for parser property tests. Keep the entire stream
-- reproducible from OBSIDIAN_FUZZ_SEED, including on different CI platforms.
local M = {}

local modulus = 2147483647

local Generator = {}
Generator.__index = Generator

function Generator.new(seed)
  return setmetatable({ state = seed }, Generator)
end

function Generator:int(max)
  self.state = (self.state * 48271) % modulus
  return self.state % max + 1
end

function Generator:pick(items)
  return items[self:int(#items)]
end

local atoms = {
  "plain",
  "two words",
  "#tag",
  "#你好",
  "#123",
  "\\#escaped",
  "[[note]]",
  "![[note#^block]]",
  "[text](note.md#Heading)",
  "[^footnote]",
  "<https://example.com>",
  "`[[hidden]] #hidden`",
  "<!-- #hidden [[hidden]] -->",
  "%% [[hidden]] #hidden %%",
  "[[unclosed",
  "]]",
  "[x](bad",
  "#mañana",
  "a#not-a-tag",
  "é🎵",
  "\\`",
  "``",
  "<!--",
  "%%",
  " ",
  "",
}

function Generator:line()
  if self:int(20) == 1 then
    -- Exercise long runs of delimiters without making CI input unbounded.
    return string.rep(self:pick { "[[", "]]", "`", "<!--", "%%", "#tag " }, self:int(80))
  end
  local parts = {}
  for _ = 1, self:int(8) do
    parts[#parts + 1] = self:pick(atoms)
  end
  return table.concat(parts, self:pick { " ", "", "  " })
end

local block_lines = {
  "---",
  "key: value",
  "```lua",
  "```",
  "~~~",
  "    indented",
  "",
  "- item",
  "> quote",
  "<!--",
  "-->",
  "%%",
  "# heading",
}

function Generator:document()
  local lines = {}
  for _ = 1, self:int(8) do
    lines[#lines + 1] = self:int(3) == 1 and self:pick(block_lines) or self:line()
  end
  return lines
end

local yaml_strings = {
  "plain",
  "hello world",
  "",
  " leading",
  "trailing ",
  "true",
  "null",
  "yes",
  "2026-03-04",
  "#tag",
  "[[note]]",
  "a: b",
  "it's here",
  'a "quote"',
  "a\\b",
  "é🎵",
}

function Generator:yaml_value()
  return self:pick(yaml_strings)
end

function Generator:yaml_document()
  local tags = {}
  for _ = 1, self:int(4) do
    tags[#tags + 1] = self:yaml_value()
  end
  return {
    title = self:yaml_value(),
    tags = tags,
    meta = { author = self:yaml_value(), published = self:int(2) == 1 },
    count = self:int(100) - 1,
  }
end

local function environment_integer(name, default, max)
  local value = os.getenv(name)
  if value == nil or value == "" then
    return default
  end
  local number = tonumber(value)
  assert(number and number % 1 == 0 and number >= 1 and number <= max, name .. " must be an integer from 1 to " .. max)
  return number
end

M.seed = environment_integer("OBSIDIAN_FUZZ_SEED", 1, modulus - 1)
M.cases = environment_integer("OBSIDIAN_FUZZ_CASES", 100, 100000)

---Run one property with a separate stream and report the exact failing input.
function M.run(name, offset, generate, check)
  local rng = Generator.new((M.seed + offset - 1) % (modulus - 1) + 1)
  for iteration = 1, M.cases do
    local input = generate(rng)
    local ok, err = pcall(check, input)
    if not ok then
      error(("%s: seed=%d iteration=%d input=%s\n%s"):format(name, M.seed, iteration, vim.inspect(input), err), 0)
    end
  end
end

return M
