--- Source-preserving Markdown exclusion scanner.
---
--- This module deliberately has no buffer or Tree-sitter dependency. It recognizes
--- only syntax that makes ordinary Markdown actions unsafe: frontmatter, code, and
--- comments. Coordinates are zero-based byte offsets and ranges are half-open.
local Pos = require "obsidian.pos"
local Range = require "obsidian.range"

local M = {}

--- Regions that suppress ordinary Markdown body actions. Consumers with a
--- narrower policy (for example frontmatter completion) should select kinds
--- explicitly instead.
M.BODY_EXCLUSIONS = {
  frontmatter = true,
  fenced_code = true,
  indented_code = true,
  code_span = true,
  html_comment = true,
  obsidian_comment = true,
  html_block = true,
}

M.COMMENTS = { html_comment = true, obsidian_comment = true }
M.CODE_BLOCKS = { fenced_code = true, indented_code = true }

---@alias obsidian.parse.document.RegionKind
---| "frontmatter"
---| "fenced_code"
---| "indented_code"
---| "code_span"
---| "html_comment"
---| "obsidian_comment"
---| "html_block"

---@class obsidian.parse.document.Region
---@field kind obsidian.parse.document.RegionKind
---@field range obsidian.Range
---@field termination "delimiter"|"block_end"|"eof"|"incomplete"
---@field opener_range obsidian.Range?
---@field closer_range obsidian.Range?
---@field body_range obsidian.Range?

---@class obsidian.parse.Document
---@field lines string[]
---@field regions obsidian.parse.document.Region[]
---@field frontmatter obsidian.parse.document.Region?
---@field private _by_kind table<string, obsidian.parse.document.Region[]>
---@field private _prefix_max_end obsidian.Pos[]
local Document = {}
Document.__index = Document

local BOM = "\239\187\191"

---@param row integer
---@param line string
---@return obsidian.Range
local function line_range(row, line)
  return Range.new(row, 0, row, #line)
end

---@param row integer
---@param col integer
---@param length integer
---@return obsidian.Range
local function token_range(row, col, length)
  return Range.new(row, col, row, col + length)
end

---@param a obsidian.Pos
---@param b obsidian.Pos
---@return boolean
local function pos_lt(a, b)
  return Pos.compare(a, b) < 0
end

---@param a obsidian.parse.document.Region
---@param b obsidian.parse.document.Region
---@return boolean
local function region_less(a, b)
  local by_start = Pos.compare(Range.start_pos(a.range), Range.start_pos(b.range))
  if by_start ~= 0 then
    return by_start < 0
  end
  -- Put an enclosing region first (notably html_block before html_comment).
  local by_end = Pos.compare(Range.end_pos(a.range), Range.end_pos(b.range))
  if by_end ~= 0 then
    return by_end > 0
  end
  return a.kind < b.kind
end

---@param kinds nil|string|string[]|table<string, boolean>
---@return table<string, boolean>?
local function normalize_kinds(kinds)
  if kinds == nil then
    return nil
  elseif type(kinds) == "string" then
    return { [kinds] = true }
  end
  assert(type(kinds) == "table", "kinds must be a string or table")
  local result = {}
  for key, value in pairs(kinds) do
    if type(key) == "number" then
      assert(type(value) == "string", "kind list entries must be strings")
      result[value] = true
    elseif value then
      assert(type(key) == "string", "kind set keys must be strings")
      result[key] = true
    end
  end
  return result
end

---@param self obsidian.parse.Document
---@param pos obsidian.Pos
local function validate_pos(self, pos)
  assert(type(pos) == "table", "position required")
  Pos.new(pos.row, pos.col)
  assert(pos.row < #self.lines, "position row is outside the document")
  assert(pos.col <= #self.lines[pos.row + 1], "position column is outside the document")
end

---@param self obsidian.parse.Document
---@param range obsidian.Range
local function validate_range(self, range)
  assert(type(range) == "table", "range required")
  Range.new(range.start_row, range.start_col, range.end_row, range.end_col)
  local count = #self.lines
  assert(range.start_row <= count and range.end_row <= count, "range row is outside the document")
  assert(range.start_row < count or range.start_col == 0, "document sentinel column must be zero")
  assert(range.end_row < count or range.end_col == 0, "document sentinel column must be zero")
  if range.start_row < count then
    assert(range.start_col <= #self.lines[range.start_row + 1], "range start column is outside the document")
  end
  if range.end_row < count then
    assert(range.end_col <= #self.lines[range.end_row + 1], "range end column is outside the document")
  end
end

---@param regions obsidian.parse.document.Region[]
---@param pos obsidian.Pos
---@param inclusive boolean
---@return integer
local function last_region_start(regions, pos, inclusive)
  local low, high, result = 1, #regions, 0
  while low <= high do
    local middle = math.floor((low + high) / 2)
    local comparison = Pos.compare(Range.start_pos(regions[middle].range), pos)
    if comparison < 0 or (inclusive and comparison == 0) then
      result = middle
      low = middle + 1
    else
      high = middle - 1
    end
  end
  return result
end

--- Return syntax regions enclosing a source position.
---@param pos obsidian.Pos
---@return { frontmatter: obsidian.parse.document.Region?, code_block: obsidian.parse.document.Region?, code_span: obsidian.parse.document.Region?, comment: obsidian.parse.document.Region?, html_block: obsidian.parse.document.Region? }
Document.context_at = function(self, pos)
  validate_pos(self, pos)
  local context = {}
  local index = last_region_start(self.regions, pos, true)
  while index > 0 and Pos.compare(self._prefix_max_end[index], pos) > 0 do
    local region = self.regions[index]
    if Range.contains_pos(region.range, pos) then
      if region.kind == "frontmatter" then
        context.frontmatter = region
      elseif region.kind == "fenced_code" or region.kind == "indented_code" then
        context.code_block = region
      elseif region.kind == "code_span" then
        context.code_span = region
      elseif region.kind == "html_comment" or region.kind == "obsidian_comment" then
        context.comment = region
      elseif region.kind == "html_block" then
        context.html_block = region
      end
    end
    index = index - 1
  end
  return context
end

--- Test for a nonempty overlap. Touching endpoints and empty ranges do not overlap.
---@param range obsidian.Range
---@param kinds nil|string|string[]|table<string, boolean>
---@return boolean
Document.intersects = function(self, range, kinds)
  validate_range(self, range)
  if Range.is_empty(range) then
    return false
  end
  local wanted = normalize_kinds(kinds)
  local range_start, range_end = Range.start_pos(range), Range.end_pos(range)
  local index = last_region_start(self.regions, range_end, false)
  while index > 0 and pos_lt(range_start, self._prefix_max_end[index]) do
    local region = self.regions[index]
    if pos_lt(range_start, Range.end_pos(region.range)) and (wanted == nil or wanted[region.kind]) then
      return true
    end
    index = index - 1
  end
  return false
end

--- Return matching regions clipped to one physical row.
---@param row integer
---@param kinds nil|string|string[]|table<string, boolean>
---@return obsidian.Range[]
Document.ranges_on_row = function(self, row, kinds)
  assert(type(row) == "number" and row >= 0 and row % 1 == 0, "row must be a nonnegative integer")
  assert(row < #self.lines, "row is outside the document")
  local wanted = normalize_kinds(kinds)
  local reversed = {}
  local row_start, row_end = Pos.new(row, 0), Pos.new(row, #self.lines[row + 1])
  local index = last_region_start(self.regions, row_end, true)
  while index > 0 and pos_lt(row_start, self._prefix_max_end[index]) do
    local region = self.regions[index]
    local start, finish = Range.start_pos(region.range), Range.end_pos(region.range)
    if Pos.compare(start, row_end) <= 0 and (wanted == nil or wanted[region.kind]) then
      local clipped_start = Pos.compare(start, row_start) < 0 and row_start or start
      local clipped_end = Pos.compare(finish, row_end) > 0 and row_end or finish
      if pos_lt(clipped_start, clipped_end) then
        reversed[#reversed + 1] = Range.from_positions(clipped_start, clipped_end)
      end
    end
    index = index - 1
  end
  local result = {}
  for reversed_index = #reversed, 1, -1 do
    result[#result + 1] = reversed[reversed_index]
  end
  return result
end

---@param line string
---@param index integer 1-based byte index
---@return integer
local function visual_column(line, index)
  local column = 0
  for byte = 1, index - 1 do
    if line:sub(byte, byte) == "\t" then
      column = column + (4 - (column % 4))
    else
      column = column + 1
    end
  end
  return column
end

---@param line string
---@param index integer 1-based byte index
---@return integer index
---@return integer columns
local function consume_whitespace(line, index)
  local start_col = visual_column(line, index)
  local column = start_col
  while index <= #line do
    local char = line:sub(index, index)
    if char == " " then
      column = column + 1
      index = index + 1
    elseif char == "\t" then
      column = column + (4 - (column % 4))
      index = index + 1
    else
      break
    end
  end
  return index, column - start_col
end

---@param line string
---@param index integer
---@param maximum integer
---@return integer index
---@return integer columns
local function consume_up_to(line, index, maximum)
  local column = visual_column(line, index)
  local consumed = 0
  while index <= #line do
    local char = line:sub(index, index)
    local width
    if char == " " then
      width = 1
    elseif char == "\t" then
      width = 4 - (column % 4)
    else
      break
    end
    if consumed + width > maximum then
      break
    end
    consumed = consumed + width
    column = column + width
    index = index + 1
  end
  return index, consumed
end

---@param line string
---@param index integer
---@param wanted integer
---@return integer? index
local function consume_columns(line, index, wanted)
  local column = visual_column(line, index)
  local consumed = 0
  while index <= #line and consumed < wanted do
    local char = line:sub(index, index)
    local width
    if char == " " then
      width = 1
    elseif char == "\t" then
      width = 4 - (column % 4)
    else
      return nil
    end
    consumed = consumed + width
    column = column + width
    index = index + 1
  end
  if consumed < wanted then
    return nil
  end
  return index
end

---@param line string
---@param index integer
---@return integer? marker end (exclusive)
local function list_marker_end(line, index)
  local char = line:sub(index, index)
  local finish
  if char == "-" or char == "+" or char == "*" then
    finish = index + 1
  else
    local digits = line:sub(index):match "^%d+"
    if digits == nil or #digits > 9 then
      return nil
    end
    local delimiter = line:sub(index + #digits, index + #digits)
    if delimiter ~= "." and delimiter ~= ")" then
      return nil
    end
    finish = index + #digits + 1
  end
  local following = line:sub(finish, finish)
  if following == " " or following == "\t" or following == "" then
    return finish
  end
end

---@class obsidian.parse.document.Container
---@field kind "quote"|"list"
---@field width integer?

--- Strip explicit quote/list markers and up to three spaces before block syntax.
---@param line string
---@param initial_index integer?
---@return integer content_index
---@return obsidian.parse.document.Container[] containers
---@return integer remaining_indent
local function block_prefix(line, initial_index)
  local index = initial_index or 1
  local containers = {}
  while true do
    local stage_start = index
    local after_indent = consume_up_to(line, index, 3)
    index = after_indent
    if line:sub(index, index) == ">" then
      index = index + 1
      local following = line:sub(index, index)
      if following == " " or following == "\t" then
        index = index + 1
      end
      containers[#containers + 1] = { kind = "quote" }
    else
      local marker_end = list_marker_end(line, index)
      if marker_end == nil then
        index = stage_start
        break
      end
      index = marker_end
      local whitespace_end, whitespace = consume_whitespace(line, index)
      if whitespace > 0 then
        -- CommonMark treats 1-4 columns as marker padding. Five or more leaves
        -- all but one column as content indentation.
        if whitespace <= 4 then
          index = whitespace_end
        else
          index = index + 1
        end
      end
      containers[#containers + 1] = {
        kind = "list",
        width = visual_column(line, index) - visual_column(line, stage_start),
      }
    end
  end
  local content, indent = consume_whitespace(line, index)
  return content, containers, indent
end

---@param line string
---@param containers obsidian.parse.document.Container[]
---@param consume_final_indent boolean?
---@return integer?
local function continue_container(line, containers, consume_final_indent)
  local index = 1
  for _, container in ipairs(containers) do
    if container.kind == "quote" then
      index = consume_up_to(line, index, 3)
      if line:sub(index, index) ~= ">" then
        return nil
      end
      index = index + 1
      local char = line:sub(index, index)
      if char == " " or char == "\t" then
        index = index + 1
      end
    else
      index = consume_columns(line, index, assert(container.width, "list container width is missing"))
      if index == nil then
        return nil
      end
    end
  end
  if consume_final_indent ~= false then
    index = consume_up_to(line, index, 3)
  end
  return index
end

---@param containers obsidian.parse.document.Container[]
---@return boolean
local function has_list_container(containers)
  for _, container in ipairs(containers) do
    if container.kind == "list" then
      return true
    end
  end
  return false
end

---@param containers obsidian.parse.document.Container[]
---@return boolean
local function has_quote_container(containers)
  for _, container in ipairs(containers) do
    if container.kind == "quote" then
      return true
    end
  end
  return false
end

---@param line string
---@param index integer
---@return string? char
---@return integer? length
local function fence_run(line, index)
  local char = line:sub(index, index)
  if char ~= "`" and char ~= "~" then
    return nil
  end
  local finish = index
  while line:sub(finish, finish) == char do
    finish = finish + 1
  end
  local length = finish - index
  if length < 3 then
    return nil
  end
  return char, length
end

---@param line string
---@param index integer
---@return string? char
---@return integer? length
local function fence_opener(line, index)
  local char, length = fence_run(line, index)
  if char == nil then
    return nil
  end
  if char == "`" and line:sub(index + assert(length, "fence length is missing")):find("`", 1, true) then
    return nil
  end
  return char, length
end

---@param line string
---@param index integer
---@param char string
---@param minimum integer
---@return integer? exclusive byte index
local function fence_closer(line, index, char, minimum)
  if line:sub(index, index) ~= char then
    return nil
  end
  local finish = index
  while line:sub(finish, finish) == char do
    finish = finish + 1
  end
  if finish - index < minimum or not line:sub(finish):match "^[ \t]*$" then
    return nil
  end
  return finish
end

---@param line string
---@param index integer
---@return boolean
local function escaped(line, index)
  local count = 0
  index = index - 1
  while index > 0 and line:sub(index, index) == "\\" do
    count = count + 1
    index = index - 1
  end
  return count % 2 == 1
end

---@param line string
---@return boolean
local function blank(line)
  return line:match "^[ \t]*$" ~= nil
end

---@param line string
---@param index integer
---@return boolean
local function thematic_break(line, index)
  local rest = line:sub(index)
  local marker = rest:sub(1, 1)
  if marker ~= "*" and marker ~= "_" and marker ~= "-" then
    return false
  end
  local count = 0
  for char in rest:gmatch "." do
    if char == marker then
      count = count + 1
    elseif char ~= " " and char ~= "\t" then
      return false
    end
  end
  return count >= 3
end

---@param line string
---@param index integer
---@return boolean
local function atx_heading(line, index)
  local rest = line:sub(index)
  local run = rest:match "^#+"
  if run == nil or #run > 6 then
    return false
  end
  local following = rest:sub(#run + 1, #run + 1)
  return following == "" or following == " " or following == "\t"
end

---@param line string
---@param containers obsidian.parse.document.Container[]?
---@return integer?
local function inline_start(line, containers)
  local container_end = continue_container(line, containers or {}, false)
  if container_end == nil then
    return nil
  end
  local index = block_prefix(line, container_end)
  return index
end

---@param line string
---@param index integer
---@return boolean
local function setext_underline(line, index)
  return line:sub(index):match "^[=-]+[ \t]*$" ~= nil
end

---@param line string
---@param containers obsidian.parse.document.Container[]?
---@return boolean
local function interrupts_inline_block(line, containers)
  if blank(line) then
    return true
  end
  local container_end = continue_container(line, containers or {}, false)
  if container_end == nil then
    return true
  end
  local index, nested, indent = block_prefix(line, container_end)
  if index > #line or indent >= 4 or #nested > 0 then
    return true
  end
  if fence_opener(line, index) ~= nil or line:sub(index, index + 3) == "<!--" then
    return true
  end
  return atx_heading(line, index) or thematic_break(line, index) or setext_underline(line, index)
end

---@param lines string[]
---@param row integer
---@param containers obsidian.parse.document.Container[]?
---@return obsidian.Pos
local function inline_block_end(lines, row, containers)
  local last = row
  while last + 1 < #lines and not interrupts_inline_block(lines[last + 2], containers) do
    last = last + 1
  end
  return Pos.new(last, #lines[last + 1])
end

---@param line string
---@param index integer
---@return integer
local function backtick_run_length(line, index)
  local finish = index
  while line:sub(finish, finish) == "`" do
    finish = finish + 1
  end
  return finish - index
end

---@param lines string[]
---@param row integer
---@param index integer 1-based
---@param run_length integer
---@param containers obsidian.parse.document.Container[]?
---@return obsidian.Pos?
local function find_code_span_close(lines, row, index, run_length, containers)
  local current_row, current_index = row, index
  while current_row < #lines do
    local line = lines[current_row + 1]
    local found = line:find("`", current_index, true)
    while found do
      local length = backtick_run_length(line, found)
      if length == run_length then
        return Pos.new(current_row, found - 1 + length)
      end
      found = line:find("`", found + length, true)
    end
    current_row = current_row + 1
    if current_row >= #lines or interrupts_inline_block(lines[current_row + 1], containers) then
      break
    end
    current_index = assert(inline_start(lines[current_row + 1], containers), "inline continuation is missing")
  end
end

---@param lines string[]
---@param row integer
---@param index integer
---@param delimiter string
---@param stop_at_block_end boolean
---@param backslash_escapes boolean?
---@param containers obsidian.parse.document.Container[]?
---@return obsidian.Pos?
local function find_delimiter(lines, row, index, delimiter, stop_at_block_end, backslash_escapes, containers)
  local current_row, current_index = row, index
  while current_row < #lines do
    local line = lines[current_row + 1]
    local found = line:find(delimiter, current_index, true)
    while found do
      if backslash_escapes == false or not escaped(line, found) then
        return Pos.new(current_row, found - 1 + #delimiter)
      end
      found = line:find(delimiter, found + #delimiter, true)
    end
    current_row = current_row + 1
    if current_row >= #lines or (stop_at_block_end and interrupts_inline_block(lines[current_row + 1], containers)) then
      break
    end
    current_index = stop_at_block_end
        and assert(inline_start(lines[current_row + 1], containers), "inline continuation is missing")
      or 1
  end
end

---@param region obsidian.parse.document.Region
---@param position obsidian.Pos
---@return boolean
local function ends_after(region, position)
  return Pos.compare(Range.end_pos(region.range), position) > 0
end

---@param lines string[]
---@return obsidian.parse.Document
M.parse = function(lines)
  assert(type(lines) == "table", "lines must be an array")
  ---@type string[]
  local source = {}
  local entry_count = 0
  for index, line in pairs(lines) do
    assert(type(index) == "number" and index >= 1 and index % 1 == 0, "lines must be a dense array")
    assert(type(line) == "string", "document lines must be strings")
    entry_count = entry_count + 1
  end
  for index = 1, entry_count do
    assert(lines[index] ~= nil, "lines must be a dense array")
    source[index] = lines[index]
  end

  local regions = {}
  local frontmatter
  local first_body_row = 0

  local function add(region)
    regions[#regions + 1] = region
    return region
  end

  -- Frontmatter is recognized before all Markdown block syntax.
  if #source > 0 then
    local first = assert(source[1], "first line is missing")
    local delimiter_col = first:sub(1, 3) == BOM and 3 or 0
    if first:sub(delimiter_col + 1):match "^%-%-%-+[ \t]*$" then
      local close_row
      for row = 1, #source - 1 do
        if source[row + 1]:match "^%-%-%-+[ \t]*$" then
          close_row = row
          break
        end
      end
      local end_row = close_row and close_row + 1 or #source
      frontmatter = add {
        kind = "frontmatter",
        range = Range.new(0, 0, end_row, 0),
        termination = close_row and "delimiter" or "eof",
        opener_range = Range.new(0, delimiter_col, 0, #first),
        closer_range = close_row and line_range(close_row, source[close_row + 1]) or nil,
        body_range = Range.new(1, 0, close_row or #source, 0),
      }
      first_body_row = end_row
    end
  end

  ---@type obsidian.parse.document.Region?
  local shield
  ---@type table<integer, obsidian.Pos>
  local failed_code_search = {}
  local paragraph_open = false
  ---@type obsidian.parse.document.Container[]?
  local active_list_containers
  local row = first_body_row
  while row < #source do
    local line = assert(source[row + 1], "document line is missing")
    local resumed_inline = false

    -- A multiline inline construct was resolved when its opener was seen. Its
    -- contents are literal, so block-looking lines cannot alter scanner state.
    if shield and ends_after(shield, Pos.new(row, 0)) then
      if shield.range.end_row > row then
        row = row + 1
      else
        local index = shield.range.end_col + 1
        shield = nil
        -- Continue below with only the visible suffix of the closing line.
        local suffix = line:sub(index)
        if suffix ~= "" then
          -- Prefixing spaces keeps byte offsets stable. `resumed_inline` keeps
          -- that suffix in the paragraph instead of treating it as a block start.
          line = string.rep(" ", index - 1) .. suffix
          resumed_inline = true
        else
          row = row + 1
          line = source[row + 1]
        end
      end
    else
      shield = nil
    end

    if row < #source and not shield then
      line = line or source[row + 1]
      if blank(line) then
        paragraph_open = false
        row = row + 1
      else
        local content_index, containers, indent
        local continued_list = false
        if active_list_containers then
          local continuation_index = continue_container(line, active_list_containers, false)
          if continuation_index then
            local nested_containers
            content_index, nested_containers, indent = block_prefix(line, continuation_index)
            containers = {}
            for _, container in ipairs(active_list_containers) do
              containers[#containers + 1] = container
            end
            for _, container in ipairs(nested_containers) do
              containers[#containers + 1] = container
            end
            if has_list_container(nested_containers) then
              active_list_containers = containers
            end
            continued_list = true
          end
        end
        if not continued_list then
          content_index, containers, indent = block_prefix(line)
          if has_list_container(containers) then
            active_list_containers = containers
          elseif content_index <= #line then
            active_list_containers = nil
          end
        end
        local fence_char, fence_length = fence_opener(line, content_index)

        if not resumed_inline and content_index > #line then
          paragraph_open = false
          row = row + 1
        elseif not resumed_inline and indent <= 3 and fence_char ~= nil then
          local opener_row = row
          local opener = token_range(row, content_index - 1, assert(fence_length, "fence length is missing"))
          local close_row, closer
          local termination = "eof"
          local scan = row + 1
          while scan < #source do
            local candidate = source[scan + 1]
            local candidate_index = continue_container(candidate, containers)
            if candidate_index == nil and (not blank(candidate) or has_quote_container(containers)) then
              termination = "block_end"
              break
            end
            if candidate_index ~= nil then
              local close_end =
                fence_closer(candidate, candidate_index, fence_char, assert(fence_length, "fence length is missing"))
              if close_end ~= nil then
                close_row = scan
                closer = Range.new(scan, candidate_index - 1, scan, close_end - 1)
                termination = "delimiter"
                scan = scan + 1
                break
              end
            end
            scan = scan + 1
          end
          add {
            kind = "fenced_code",
            range = Range.new(opener_row, 0, close_row and close_row + 1 or scan, 0),
            termination = termination,
            opener_range = opener,
            closer_range = closer,
          }
          paragraph_open = false
          row = close_row and close_row + 1 or scan
        elseif not resumed_inline and indent <= 3 and line:sub(content_index, content_index + 3) == "<!--" then
          local opener_col = content_index - 1
          local close = find_delimiter(source, row, content_index + 3, "-->", false, false, containers)
          local comment_end = close or Pos.new(#source, 0)
          local termination = close and "delimiter" or "eof"
          local block_end_row = close and close.row + 1 or #source
          local html_block = add {
            kind = "html_block",
            range = Range.new(row, 0, block_end_row, 0),
            termination = termination,
          }
          add {
            kind = "html_comment",
            range = Range.new(row, opener_col, comment_end.row, comment_end.col),
            termination = termination,
            opener_range = token_range(row, opener_col, 4),
            closer_range = close and Range.new(close.row, close.col - 3, close.row, close.col) or nil,
          }
          paragraph_open = false
          row = html_block.range.end_row
        elseif not resumed_inline and indent >= 4 and not paragraph_open then
          local start_row = row
          local scan = row
          local last_code_row = row
          while scan < #source do
            local candidate = source[scan + 1]
            if blank(candidate) then
              scan = scan + 1
            else
              local candidate_index = continue_container(candidate, containers, false)
              if candidate_index == nil then
                break
              end
              local _, candidate_indent = consume_whitespace(candidate, candidate_index)
              if candidate_indent < 4 then
                break
              end
              last_code_row = scan
              scan = scan + 1
            end
          end
          add {
            kind = "indented_code",
            range = Range.new(start_row, 0, last_code_row + 1, 0),
            termination = scan == #source and "eof" or "block_end",
          }
          paragraph_open = false
          row = last_code_row + 1
        else
          paragraph_open = true
          local ends_paragraph = atx_heading(line, content_index)
            or thematic_break(line, content_index)
            or setext_underline(line, content_index)
          local index = content_index
          local advance_row = true
          while index <= #line do
            local backtick = line:find("`", index, true)
            local html = line:find("<!--", index, true)
            local obsidian = line:find("%%", index, true)
            local found, kind = backtick, backtick and "code" or nil
            if html and (found == nil or html < found) then
              found, kind = html, "html"
            end
            if obsidian and (found == nil or obsidian < found) then
              found, kind = obsidian, "obsidian"
            end
            if found == nil then
              break
            elseif escaped(line, found) then
              index = found + (kind == "html" and 4 or kind == "obsidian" and 2 or backtick_run_length(line, found))
            elseif kind == "code" then
              local length = backtick_run_length(line, found)
              local failed_until = failed_code_search[length]
              local close
              if failed_until == nil or Pos.compare(Pos.new(row, found - 1), failed_until) >= 0 then
                close = find_code_span_close(source, row, found + length, length, containers)
                if close == nil then
                  failed_code_search[length] = inline_block_end(source, row, containers)
                end
              end
              if close then
                local region = add {
                  kind = "code_span",
                  range = Range.new(row, found - 1, close.row, close.col),
                  termination = "delimiter",
                  opener_range = token_range(row, found - 1, length),
                  closer_range = Range.new(close.row, close.col - length, close.row, close.col),
                }
                if close.row == row then
                  index = close.col + 1
                else
                  shield = region
                  advance_row = false
                  row = row + 1
                  break
                end
              else
                index = found + length
              end
            else
              local delimiter = kind == "html" and "-->" or "%%"
              local opener_length = kind == "html" and 4 or 2
              local search_start = found + opener_length - (kind == "html" and 1 or 0)
              local close =
                find_delimiter(source, row, search_start, delimiter, kind == "html", kind ~= "html", containers)
              local finish
              local termination
              if close then
                finish = close
                termination = "delimiter"
              elseif kind == "html" then
                finish = inline_block_end(source, row, containers)
                termination = "incomplete"
              else
                finish = Pos.new(#source, 0)
                termination = "eof"
              end
              local region = add {
                kind = kind == "html" and "html_comment" or "obsidian_comment",
                range = Range.new(row, found - 1, finish.row, finish.col),
                termination = termination,
                opener_range = token_range(row, found - 1, opener_length),
                closer_range = close and Range.new(close.row, close.col - #delimiter, close.row, close.col) or nil,
              }
              if close and close.row == row then
                index = close.col + 1
              elseif finish.row > row then
                shield = region
                advance_row = false
                row = row + 1
                break
              else
                break
              end
            end
          end
          if advance_row then
            if ends_paragraph then
              paragraph_open = false
            end
            row = row + 1
          end
        end
      end
    end
  end

  table.sort(regions, region_less)
  local by_kind = {}
  local prefix_max_end = {}
  local maximum_end = Pos.new(0, 0)
  for index, region in ipairs(regions) do
    local entries = by_kind[region.kind]
    if entries == nil then
      entries = {}
      by_kind[region.kind] = entries
    end
    entries[#entries + 1] = region
    local region_end = Range.end_pos(region.range)
    if Pos.compare(region_end, maximum_end) > 0 then
      maximum_end = region_end
    end
    prefix_max_end[index] = maximum_end
  end

  return setmetatable({
    lines = source,
    regions = regions,
    frontmatter = frontmatter,
    _by_kind = by_kind,
    _prefix_max_end = prefix_max_end,
  }, Document)
end

return M
