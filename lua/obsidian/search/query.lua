local M = {}

local cache = require "obsidian.cache"
local Ripgrep = require "obsidian.search.ripgrep"

local scope_list = {
  "block",
  "content",
  "file",
  "ignore-case",
  "line",
  "match-case",
  "path",
  "section",
  "tag",
  "task",
  "task-done",
  "task-todo",
}

local scopes = {}
for _, scope in ipairs(scope_list) do
  scopes[scope] = true
end

---@class obsidian.search.QueryToken
---@field kind  string
---@field value string |?
---@field pos   integer

---@class obsidian.search.QueryNode
---@field kind  string
---@field value string |?
---@field regex boolean |?
---@field scope string |?
---@field child obsidian.search.QueryNode |?
---@field left  obsidian.search.QueryNode |?
---@field right obsidian.search.QueryNode |?
---@field key   obsidian.search.QueryNode |?

---@class obsidian.search.QueryDocument
---@field path          string
---@field relative_path string
---@field filename      string
---@field lines         string[]
---@field properties    table<string, any>
---@field tags          { text: string, line: integer } []
---@field tasks         { raw: string, line: integer, state: string } []

---@class obsidian.search.QueryResult
---@field document obsidian.search.QueryDocument
---@field line     integer                       1-indexed
---@field col      integer                       1-indexed
---@field end_col  integer |?                    Quickfix-style end column (1-indexed, exclusive after normalization).
---@field score    integer
---@field context  string |?

---@param query            string
---@param allow_incomplete boolean
---@return obsidian.search.QueryToken[] |?
---@return string |?
local function tokenize(query, allow_incomplete)
  local tokens = {}
  local i = 1

  local function add(kind, value, pos)
    tokens[#tokens + 1] = { kind = kind, value = value, pos = pos }
  end

  while i <= #query do
    local char = query:sub(i, i)
    if char:match "%s" then
      i = i + 1
    elseif char == "(" then
      add("lparen", nil, i)
      i = i + 1
    elseif char == ")" then
      add("rparen", nil, i)
      i = i + 1
    elseif char == "-" then
      add("not", nil, i)
      i = i + 1
    elseif char == '"' or char == "/" then
      local start = i
      local delimiter = char
      local kind = delimiter == '"' and "phrase" or "regex"
      local value = {}
      local closed = false
      i = i + 1
      while i <= #query do
        char = query:sub(i, i)
        if char == "\\" and i < #query then
          local escaped = query:sub(i + 1, i + 1)
          if delimiter == "/" then
            value[#value + 1] = "\\" .. escaped
          else
            value[#value + 1] = escaped
          end
          i = i + 2
        elseif char == delimiter then
          closed = true
          i = i + 1
          break
        else
          value[#value + 1] = char
          i = i + 1
        end
      end
      if not closed and not allow_incomplete then
        return nil, string.format("Unclosed %s at column %d", kind, start)
      end
      add(kind, table.concat(value), start)
    elseif char == "[" then
      local start = i
      local value = {}
      local quote
      local escaped = false
      local closed = false
      i = i + 1
      while i <= #query do
        char = query:sub(i, i)
        if escaped then
          value[#value + 1] = char
          escaped = false
        elseif char == "\\" then
          value[#value + 1] = char
          escaped = true
        elseif quote then
          value[#value + 1] = char
          if char == quote then
            quote = nil
          end
        elseif char == '"' or char == "/" then
          value[#value + 1] = char
          quote = char
        elseif char == "]" then
          closed = true
          i = i + 1
          break
        else
          value[#value + 1] = char
          i = i + 1
        end
      end
      if not closed and not allow_incomplete then
        return nil, string.format("Unclosed property expression at column %d", start)
      end
      add("property", table.concat(value), start)
    else
      local start = i
      while i <= #query do
        local current_char = query:sub(i, i)
        local prefix = query:sub(start, i - 1):match "^([%a][%a%-]*):$"
        if current_char:match '[%s%(%)%[%]"]' or (current_char == "/" and prefix and scopes[prefix]) then
          break
        end
        i = i + 1
      end
      if i == start then
        i = i + 1
      end
      local value = query:sub(start, i - 1)
      add(value == "OR" and "or" or "word", value, start)
    end
  end

  return tokens
end

---@param value string
---@return string, string |?
local function split_property(value)
  local quote
  local escaped = false
  local depth = 0
  for i = 1, #value do
    local char = value:sub(i, i)
    if escaped then
      escaped = false
    elseif char == "\\" then
      escaped = true
    elseif quote then
      if char == quote then
        quote = nil
      end
    elseif char == '"' or char == "/" then
      quote = char
    elseif char == "(" then
      depth = depth + 1
    elseif char == ")" then
      depth = math.max(0, depth - 1)
    elseif char == ":" and depth == 0 then
      return vim.trim(value:sub(1, i - 1)), vim.trim(value:sub(i + 1))
    end
  end
  return vim.trim(value), nil
end

---@param query string
---@param opts  { allow_incomplete: boolean |? } |?
---@return obsidian.search.QueryNode |?
---@return string |?
function M.parse(query, opts)
  opts = opts or {}
  local tokens, token_error = tokenize(query, opts.allow_incomplete == true)
  if not tokens then
    return nil, token_error
  end
  if #tokens == 0 then
    return { kind = "all" }
  end

  local position = 1
  local parse_or = function()
    error "parser not initialized"
  end
  local parse_unary = function()
    error "parser not initialized"
  end

  local function current()
    return tokens[position]
  end

  ---@param value string
  ---@param regex boolean |?
  ---@return obsidian.search.QueryNode
  local function term(value, regex)
    return { kind = "term", value = value, regex = regex }
  end

  ---@param value string
  ---@return obsidian.search.QueryNode |?
  ---@return string |?
  local function property(value)
    local key_query, value_query = split_property(value)
    if key_query == "" then
      return nil, "Property name cannot be empty"
    end
    local key, key_error = M.parse(key_query, opts)
    if not key then
      return nil, key_error
    end
    local node = { kind = "property", key = key }
    if value_query ~= nil then
      if value_query == "" then
        node.child = term ""
      else
        local child, child_error = M.parse(value_query, opts)
        if not child then
          return nil, child_error
        end
        node.child = child
      end
    end
    return node
  end

  local function parse_primary()
    local token = current()
    if not token then
      return nil, "Expected a search term"
    end

    if token.kind == "lparen" then
      position = position + 1
      local node, err = parse_or()
      if not node then
        return nil, err
      end
      token = current()
      if token and token.kind == "rparen" then
        position = position + 1
      elseif not opts.allow_incomplete then
        return nil, "Unclosed group"
      end
      return node
    elseif token.kind == "phrase" then
      position = position + 1
      return term(token.value or "")
    elseif token.kind == "regex" then
      position = position + 1
      return term(token.value or "", true)
    elseif token.kind == "property" then
      position = position + 1
      return property(token.value or "")
    elseif token.kind ~= "word" then
      return nil, string.format("Expected a search term at column %d", token.pos)
    end

    position = position + 1
    local value = token.value or ""
    local scope, inline = value:match "^([%a][%a%-]*):(.*)$"
    if not scope or not scopes[scope] then
      return term(value)
    end
    ---@cast inline - nil

    local child
    local err
    if inline ~= "" then
      if vim.startswith(inline, "/") and vim.endswith(inline, "/") and #inline > 1 then
        child = term(inline:sub(2, -2), true)
      else
        child = term(inline)
      end
    else
      child, err = parse_unary()
      if not child then
        if opts.allow_incomplete then
          child = term ""
        else
          return nil, err
        end
      end
    end
    return { kind = "scope", scope = scope, child = child }
  end

  parse_unary = function()
    local token = current()
    if token and token.kind == "not" then
      position = position + 1
      local child, err = parse_unary()
      if not child then
        return nil, err
      end
      return { kind = "not", child = child }
    end
    return parse_primary()
  end

  local function starts_expression(token)
    return token
      and (
        token.kind == "word"
        or token.kind == "phrase"
        or token.kind == "regex"
        or token.kind == "property"
        or token.kind == "lparen"
        or token.kind == "not"
      )
  end

  local function parse_and()
    local node, err = parse_unary()
    if not node then
      return nil, err
    end
    while starts_expression(current()) do
      local right
      right, err = parse_unary()
      if not right then
        return nil, err
      end
      node = { kind = "and", left = node, right = right }
    end
    return node
  end

  parse_or = function()
    local node, err = parse_and()
    if not node then
      return nil, err
    end
    local token = current()
    while token and token.kind == "or" do
      position = position + 1
      local right
      right, err = parse_and()
      if not right then
        return nil, err
      end
      node = { kind = "or", left = node, right = right }
      token = current()
    end
    return node
  end

  local result, parse_error = parse_or()
  if not result then
    return nil, parse_error
  end
  local trailing = current()
  if trailing then
    return nil, string.format("Unexpected token at column %d", trailing.pos)
  end
  return result
end

---@param value any
---@param out   string[]
local function flatten(value, out)
  if value == vim.NIL or value == nil then
    return
  elseif type(value) == "table" then
    for key, item in pairs(value) do
      if not vim.islist(value) then
        out[#out + 1] = tostring(key)
      end
      flatten(item, out)
    end
  else
    out[#out + 1] = tostring(value)
  end
end

---@class obsidian.search.QueryContext
---@field texts          { text: string, line: integer } [] |?
---@field case_sensitive boolean |?
---@field exact          boolean |?

---@class obsidian.search.QueryMatch
---@field score   integer
---@field line    integer
---@field col     integer 0-indexed start column.
---@field end_col integer 0-indexed exclusive end column.

---@param text           string
---@param node           obsidian.search.QueryNode
---@param case_sensitive boolean
---@param exact          boolean |?
---@return integer |? start_col 0-indexed.
---@return integer |? end_col 0-indexed, exclusive.
local function find_term(text, node, case_sensitive, exact)
  local value = node.value or ""
  if node.regex then
    local ok, regex = pcall(vim.regex, (case_sensitive and "\\C" or "\\c") .. value)
    if not ok then
      return nil
    end
    return regex:match_str(text)
  end

  local original_text, original_value = text, value
  if not case_sensitive then
    text = string.lower(text)
    value = string.lower(value)
  end
  if exact then
    text = text:gsub("^#", "")
    value = value:gsub("^#", "")
    if text ~= value then
      return nil
    end
    local start = vim.startswith(original_text, "#") and not vim.startswith(original_value, "#") and 1 or 0
    return start, #original_text
  end
  local start = string.find(text, value, 1, true)
  return start and start - 1 or nil, start and start - 1 + #value or nil
end

---@param document obsidian.search.QueryDocument
---@param context  obsidian.search.QueryContext
---@return { text: string, line: integer } []
local function default_texts(document, context)
  if context.texts then
    return context.texts
  end
  local texts = { { text = document.filename, line = 0 } }
  for line_number, line in ipairs(document.lines) do
    texts[#texts + 1] = { text = line, line = line_number }
  end
  return texts
end

---@param node     obsidian.search.QueryNode
---@param document obsidian.search.QueryDocument
---@param context  obsidian.search.QueryContext
---@return obsidian.search.QueryMatch |?
local function evaluate(node, document, context)
  if node.kind == "all" then
    return { score = 0, line = 0, col = 0, end_col = 0 }
  elseif node.kind == "term" then
    local best
    for _, candidate in ipairs(default_texts(document, context)) do
      local col, end_col = find_term(candidate.text, node, context.case_sensitive == true, context.exact)
      if col then
        local score = candidate.line == 0 and 50 or 10
        if candidate.line == 0 and col == 0 then
          score = #(node.value or "") == #candidate.text and 100 or 70
        end
        if not best or score > best.score then
          best = { score = score, line = candidate.line, col = col, end_col = end_col or col }
        end
      end
    end
    return best
  elseif node.kind == "not" then
    if evaluate(assert(node.child, "not node is missing its child"), document, context) then
      return nil
    end
    return { score = 0, line = 0, col = 0, end_col = 0 }
  elseif node.kind == "and" then
    local left = evaluate(assert(node.left, "and node is missing its left child"), document, context)
    if not left then
      return nil
    end
    local right = evaluate(assert(node.right, "and node is missing its right child"), document, context)
    if not right then
      return nil
    end
    local located = left.line > 0 and left or right
    return {
      score = left.score + right.score,
      line = located.line,
      col = located.col,
      end_col = located.end_col,
    }
  elseif node.kind == "or" then
    local left = evaluate(assert(node.left, "or node is missing its left child"), document, context)
    local right = evaluate(assert(node.right, "or node is missing its right child"), document, context)
    if not left then
      return right
    elseif not right or left.score >= right.score then
      return left
    else
      return right
    end
  elseif node.kind == "property" then
    for key, value in pairs(document.properties) do
      local key_match = evaluate(assert(node.key, "property node is missing its key"), document, {
        texts = { { text = tostring(key), line = 1 } },
        case_sensitive = context.case_sensitive,
      })
      if key_match then
        if not node.child then
          return { score = 20, line = 0, col = 0, end_col = 0 }
        end

        local child = node.child
        ---@cast child - nil
        local is_empty = value == vim.NIL or value == nil
        if child.kind == "term" and not child.regex and string.lower(child.value or "") == "null" then
          if is_empty then
            return { score = 25, line = 0, col = 0, end_col = 0 }
          end
        else
          local values = {}
          flatten(value, values)
          local comparison, expected
          if child.kind == "term" and not child.regex then
            comparison, expected = (child.value or ""):match "^(<=?)(.*)$"
            if not comparison then
              comparison, expected = (child.value or ""):match "^(>=?)(.*)$"
            end
          end
          ---@cast expected - nil
          for _, item in ipairs(values) do
            local matched = false
            if comparison then
              local actual_number, expected_number = tonumber(item), tonumber(expected)
              local actual = actual_number or string.lower(item)
              local wanted = expected_number or string.lower(expected)
              if type(actual) == type(wanted) then
                matched = (comparison == "<" and actual < wanted)
                  or (comparison == "<=" and actual <= wanted)
                  or (comparison == ">" and actual > wanted)
                  or (comparison == ">=" and actual >= wanted)
              end
            else
              matched = evaluate(child, document, {
                texts = { { text = item, line = 1 } },
                case_sensitive = context.case_sensitive,
              }) ~= nil
            end
            if matched then
              return { score = 25, line = 0, col = 0, end_col = 0 }
            end
          end
        end
      end
    end
    return nil
  end

  local scope = assert(node.scope, "scope node is missing its name")
  local child = assert(node.child, "scope node is missing its child")
  if scope == "match-case" or scope == "ignore-case" then
    return evaluate(child, document, {
      texts = context.texts,
      exact = context.exact,
      case_sensitive = scope == "match-case",
    })
  elseif scope == "file" then
    return evaluate(child, document, {
      texts = { { text = document.filename, line = 0 } },
      case_sensitive = context.case_sensitive,
    })
  elseif scope == "path" then
    return evaluate(child, document, {
      texts = { { text = document.relative_path, line = 0 } },
      case_sensitive = context.case_sensitive,
    })
  elseif scope == "content" then
    local texts = {}
    for line_number, line in ipairs(document.lines) do
      texts[#texts + 1] = { text = line, line = line_number }
    end
    return evaluate(child, document, { texts = texts, case_sensitive = context.case_sensitive })
  elseif scope == "tag" then
    for _, tag in ipairs(document.tags) do
      local match = evaluate(child, document, {
        texts = { { text = tag.text, line = tag.line } },
        case_sensitive = context.case_sensitive,
        exact = true,
      })
      if match then
        match.score = match.score + 20
        return match
      end
    end
    return nil
  end

  local groups = {}
  if scope == "line" then
    for line_number, line in ipairs(document.lines) do
      groups[#groups + 1] = { { text = line, line = line_number } }
    end
  elseif scope == "block" then
    local block = {}
    for line_number, line in ipairs(document.lines) do
      if line:match "^%s*$" then
        if #block > 0 then
          groups[#groups + 1] = block
          block = {}
        end
      else
        block[#block + 1] = { text = line, line = line_number }
      end
    end
    if #block > 0 then
      groups[#groups + 1] = block
    end
  elseif scope == "section" then
    local section = {}
    for line_number, line in ipairs(document.lines) do
      if line:match "^%s*#+%s+" and #section > 0 then
        groups[#groups + 1] = section
        section = {}
      end
      section[#section + 1] = { text = line, line = line_number }
    end
    if #section > 0 then
      groups[#groups + 1] = section
    end
  else
    for _, task in ipairs(document.tasks or {}) do
      local line = task.raw
      local line_number = task.line
      local status = task.state
      local is_task = status ~= nil
      local accepted = scope == "task"
        or (scope == "task-done" and status and status:lower() == "x")
        or (scope == "task-todo" and status == " ")
      if is_task and accepted then
        groups[#groups + 1] = { { text = line, line = line_number } }
      end
    end
  end

  for _, texts in ipairs(groups) do
    local match = evaluate(child, document, { texts = texts, case_sensitive = context.case_sensitive })
    if match then
      match.score = match.score + 20
      return match
    end
  end
  return nil
end

---@param documents obsidian.search.QueryDocument[]
---@param ast       obsidian.search.QueryNode
---@return obsidian.search.QueryResult[]
local function search_ast(documents, ast)
  local results = {}
  for _, document in ipairs(documents) do
    local match = evaluate(ast, document, {})
    if match then
      results[#results + 1] = {
        document = document,
        line = math.max(1, match.line),
        col = match.col + 1,
        end_col = match.line > 0 and match.end_col + 1 or nil,
        score = match.score,
        context = match.line > 0 and document.lines[match.line] or nil,
      }
    end
  end
  table.sort(results, function(a, b)
    if a.score == b.score then
      return string.lower(a.document.relative_path) < string.lower(b.document.relative_path)
    end
    return a.score > b.score
  end)
  return results
end

---@param node obsidian.search.QueryNode
---@param has_text_context boolean
---@return boolean
local function requires_content(node, has_text_context)
  if node.kind == "all" then
    return false
  elseif node.kind == "term" then
    return not has_text_context
  elseif node.kind == "not" then
    return requires_content(assert(node.child, "not node is missing its child"), has_text_context)
  elseif node.kind == "and" or node.kind == "or" then
    return requires_content(assert(node.left, node.kind .. " node is missing its left child"), has_text_context)
      or requires_content(assert(node.right, node.kind .. " node is missing its right child"), has_text_context)
  elseif node.kind == "property" then
    return (node.child and requires_content(node.child, true)) or false
  end

  local scope = assert(node.scope, "scope node is missing its name")
  if scope == "content" or scope == "line" or scope == "block" or scope == "section" then
    return true
  elseif scope == "match-case" or scope == "ignore-case" then
    return requires_content(assert(node.child, "case scope is missing its child"), has_text_context)
  else
    return requires_content(assert(node.child, "scope node is missing its child"), true)
  end
end

---@param path string
---@param row table
---@param lines string[]|nil
---@return obsidian.search.QueryDocument
local function document_from_row(path, row, lines)
  local tags = vim.deepcopy(row.tag_locations or {})
  if #tags == 0 then
    for _, tag in ipairs(row.tags or {}) do
      tags[#tags + 1] = { text = vim.startswith(tag, "#") and tag or "#" .. tag, line = 1 }
    end
  end
  return {
    path = path,
    relative_path = row.relative_path,
    filename = row.filename,
    lines = lines or {},
    properties = vim.deepcopy((row.frontmatter and row.frontmatter.values) or row.properties or {}),
    tags = tags,
    tasks = vim.deepcopy(row.tasks or {}),
  }
end

---@param path string
---@param root string
---@return boolean
local function is_under(path, root)
  root = vim.fs.normalize(root):gsub("/+$", "")
  path = vim.fs.normalize(path)
  return path == root or vim.startswith(path, root .. "/")
end

---@class obsidian.search.QueryOpts
---@field root string|obsidian.Path|nil
---@field allow_incomplete boolean|nil
---@field include_canvas boolean|nil

---Execute an Obsidian query against the validated cache universe. File content
---is obtained only through ripgrep when the AST requires it.
---@param query string
---@param opts obsidian.search.QueryOpts|nil
---@param callback fun(items: obsidian.search.QueryResult[], err: string|nil)
---@return fun() cancel
function M.search(query, opts, callback)
  opts = opts or {}
  local ast, parse_error = M.parse(query, { allow_incomplete = opts.allow_incomplete == true })
  local cancelled = false
  local completed = false
  local cancel_ready
  local cancel_ripgrep

  local function finish(items, err)
    if cancelled or completed then
      return
    end
    completed = true
    callback(items, err)
  end

  if not ast then
    finish({}, parse_error)
    return function()
      cancelled = true
    end
  end
  if not cache.is_enabled() then
    finish({}, "Obsidian query search requires the cache to be enabled")
    return function()
      cancelled = true
    end
  end

  local function execute(attempt)
    if cancelled then
      return
    end
    local snapshot = cache.notes.snapshot()
    local root = vim.fs.normalize(tostring(opts.root or snapshot.vault))
    if not is_under(root, snapshot.vault) then
      finish({}, "Query root is outside the cached vault")
      return
    end

    local paths = {}
    local rows = {}
    for path, row in pairs(snapshot.rows) do
      path = vim.fs.normalize(path)
      if is_under(path, root) and (opts.include_canvas ~= false or row.kind ~= "canvas") then
        paths[#paths + 1] = path
        rows[path] = row
      end
    end
    table.sort(paths, function(a, b)
      return a:lower() < b:lower()
    end)

    local function publish(lines_by_path)
      if cancelled then
        return
      end
      if cache.generation() ~= snapshot.generation then
        if attempt == 0 then
          execute(1)
        else
          finish({}, "Cache changed while the query was running")
        end
        return
      end
      local documents = {}
      for _, path in ipairs(paths) do
        documents[#documents + 1] = document_from_row(path, rows[path], lines_by_path and lines_by_path[path])
      end
      finish(search_ast(documents, ast), nil)
    end

    if not requires_content(ast, false) then
      publish(nil)
      return
    end
    if vim.fn.executable "rg" ~= 1 then
      finish({}, "Obsidian query search requires ripgrep for content queries")
      return
    end
    cancel_ripgrep = Ripgrep.read_lines_async(paths, function(result, err)
      if err then
        finish({}, err)
      else
        publish(assert(result).lines)
      end
    end)
  end

  cancel_ready = cache.when_ready(function()
    execute(0)
  end)

  return function()
    if cancelled then
      return
    end
    cancelled = true
    if cancel_ready then
      cancel_ready()
    end
    if cancel_ripgrep then
      cancel_ripgrep()
    end
  end
end

return M
