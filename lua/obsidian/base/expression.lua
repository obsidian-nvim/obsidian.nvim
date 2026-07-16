local M = {}
local property = require "obsidian.base.property"

---@class obsidian.base.Token
---@field kind string
---@field value any
---@field raw string
---@field start integer
---@field finish integer

local two_char_operators = {
  ["=="] = true,
  ["!="] = true,
  [">="] = true,
  ["<="] = true,
  ["&&"] = true,
  ["||"] = true,
}

local single_tokens = {
  ["+"] = "operator",
  ["-"] = "operator",
  ["*"] = "operator",
  ["/"] = "operator",
  ["%"] = "operator",
  ["!"] = "operator",
  [">"] = "operator",
  ["<"] = "operator",
  ["("] = "(",
  [")"] = ")",
  ["["] = "[",
  ["]"] = "]",
  ["."] = ".",
  [","] = ",",
}

local escapes = {
  b = "\b",
  f = "\f",
  n = "\n",
  r = "\r",
  t = "\t",
  v = "\v",
}

---@param diagnostics obsidian.base.Diagnostic[]
---@param code string
---@param message string
---@param start integer
---@param finish integer
local function diagnostic(diagnostics, code, message, start, finish)
  diagnostics[#diagnostics + 1] = {
    code = code,
    message = message,
    severity = "error",
    range = { start = start, finish = finish },
  }
end

---@param source string
---@return obsidian.base.Token[]
---@return obsidian.base.Diagnostic[]
local function lex(source)
  local tokens = {}
  local diagnostics = {}
  local index = 1

  ---@param kind string
  ---@param value any
  ---@param start_index integer
  ---@param finish_index integer
  local function add(kind, value, start_index, finish_index)
    tokens[#tokens + 1] = {
      kind = kind,
      value = value,
      raw = source:sub(start_index, finish_index - 1),
      start = start_index - 1,
      finish = finish_index - 1,
    }
  end

  while index <= #source do
    local char = source:sub(index, index)
    if char:match "%s" then
      index = index + 1
    elseif char == '"' or char == "'" then
      local start_index = index
      local quote = char
      local value = {}
      local closed = false
      index = index + 1
      while index <= #source do
        char = source:sub(index, index)
        if char == quote then
          index = index + 1
          closed = true
          break
        elseif char == "\\" then
          local escaped = source:sub(index + 1, index + 1)
          if escaped == "" then
            break
          end
          value[#value + 1] = escapes[escaped] or escaped
          index = index + 2
        else
          value[#value + 1] = char
          index = index + 1
        end
      end
      add("string", table.concat(value), start_index, index)
      if not closed then
        diagnostic(
          diagnostics,
          "expression.unterminated-string",
          "unterminated string literal",
          start_index - 1,
          index - 1
        )
      end
    elseif char:match "%d" or (char == "." and source:sub(index + 1, index + 1):match "%d") then
      local start_index = index
      local rest = source:sub(index)
      local raw = rest:match "^%d+%.?%d*[eE][+-]?%d+"
        or rest:match "^%.%d+[eE][+-]?%d+"
        or rest:match "^%d+%.?%d*"
        or rest:match "^%.%d+"
      assert(raw ~= nil, "number token did not match")
      index = index + #raw
      add("number", tonumber(raw), start_index, index)
    elseif char:match "[%a_]" then
      local start_index = index
      index = index + 1
      while index <= #source and source:sub(index, index):match "[%w_]" do
        index = index + 1
      end
      local raw = source:sub(start_index, index - 1)
      if raw == "true" then
        add("literal", true, start_index, index)
      elseif raw == "false" then
        add("literal", false, start_index, index)
      elseif raw == "null" then
        add("literal", vim.NIL, start_index, index)
      else
        add("identifier", raw, start_index, index)
      end
    else
      local pair = source:sub(index, index + 1)
      if two_char_operators[pair] then
        add("operator", pair, index, index + 2)
        index = index + 2
      elseif single_tokens[char] then
        add(single_tokens[char], char, index, index + 1)
        index = index + 1
      else
        diagnostic(diagnostics, "expression.invalid-token", ("unexpected character %q"):format(char), index - 1, index)
        index = index + 1
      end
    end
  end

  tokens[#tokens + 1] = {
    kind = "eof",
    value = nil,
    raw = "",
    start = #source,
    finish = #source,
  }
  return tokens, diagnostics
end

local binary_precedence = {
  ["||"] = 1,
  ["&&"] = 2,
  ["=="] = 3,
  ["!="] = 3,
  [">"] = 4,
  ["<"] = 4,
  [">="] = 4,
  ["<="] = 4,
  ["+"] = 5,
  ["-"] = 5,
  ["*"] = 6,
  ["/"] = 6,
  ["%"] = 6,
}

---@class obsidian.base.ExpressionParser
---@field tokens obsidian.base.Token[]
---@field diagnostics obsidian.base.Diagnostic[]
---@field index integer
local Parser = {}
Parser.__index = Parser

---@return obsidian.base.Token
function Parser:current()
  local token = assert(self.tokens[self.index], "expression parser advanced past EOF")
  return token
end

---@param kind string
---@return obsidian.base.Token?
function Parser:take(kind)
  local token = self:current()
  if token.kind ~= kind then
    return nil
  end
  self.index = self.index + 1
  return token
end

---@param kind string
---@param message string
---@return obsidian.base.Token?
function Parser:expect(kind, message)
  local token = self:take(kind)
  if token ~= nil then
    return token
  end
  local current = self:current()
  diagnostic(self.diagnostics, "expression.expected-token", message, current.start, current.finish)
  return nil
end

---@return obsidian.base.Expression?
function Parser:parse_primary()
  local token = self:current()
  if token.kind == "string" or token.kind == "number" or token.kind == "literal" then
    self.index = self.index + 1
    return {
      kind = "literal",
      value = token.value,
      raw = token.raw,
      range = { start = token.start, finish = token.finish },
    }
  elseif token.kind == "identifier" then
    self.index = self.index + 1
    return {
      kind = "identifier",
      name = token.value,
      reference = property.from_identifier(token.value),
      range = { start = token.start, finish = token.finish },
    }
  elseif token.kind == "(" then
    self.index = self.index + 1
    local expression = self:parse_expression(1)
    local close = self:expect(")", "expected ')' after expression")
    if expression == nil then
      return nil
    end
    return {
      kind = "group",
      expression = expression,
      range = { start = token.start, finish = close and close.finish or expression.range.finish },
    }
  end

  diagnostic(self.diagnostics, "expression.expected-expression", "expected an expression", token.start, token.finish)
  if token.kind ~= "eof" then
    self.index = self.index + 1
  end
  return nil
end

---@return obsidian.base.Expression?
function Parser:parse_prefix()
  local token = self:current()
  if token.kind == "operator" and (token.value == "!" or token.value == "-" or token.value == "+") then
    self.index = self.index + 1
    local operand = self:parse_prefix()
    if operand == nil then
      return nil
    end
    return {
      kind = "unary",
      operator = token.value,
      operand = operand,
      range = { start = token.start, finish = operand.range.finish },
    }
  end
  return self:parse_primary()
end

---@param expression obsidian.base.Expression
---@return obsidian.base.Expression
function Parser:parse_postfix(expression)
  while true do
    local token = self:current()
    if token.kind == "." then
      self.index = self.index + 1
      local property_token = self:expect("identifier", "expected a property name after '.'")
      if property_token == nil then
        return expression
      end
      expression = {
        kind = "member",
        object = expression,
        property = property_token.value,
        reference = property.from_member(expression, property_token.value),
        range = { start = expression.range.start, finish = property_token.finish },
      }
    elseif token.kind == "[" then
      self.index = self.index + 1
      local index_expression = self:parse_expression(1)
      local close = self:expect("]", "expected ']' after index expression")
      if index_expression == nil then
        return expression
      end
      expression = {
        kind = "index",
        object = expression,
        index = index_expression,
        reference = property.from_index(expression, index_expression),
        range = {
          start = expression.range.start,
          finish = close and close.finish or index_expression.range.finish,
        },
      }
    elseif token.kind == "(" then
      self.index = self.index + 1
      -- A bare identifier or member in callee position is a function/method,
      -- not a property value. Nested receiver nodes retain their references.
      expression.reference = nil
      local arguments = {}
      if self:current().kind ~= ")" then
        while true do
          local argument = self:parse_expression(1)
          if argument ~= nil then
            arguments[#arguments + 1] = argument
          end
          if self:take "," == nil then
            break
          end
        end
      end
      local close = self:expect(")", "expected ')' after arguments")
      expression = {
        kind = "call",
        callee = expression,
        arguments = arguments,
        range = {
          start = expression.range.start,
          finish = close and close.finish or self:current().start,
        },
      }
    else
      return expression
    end
  end
end

---@param min_precedence integer
---@return obsidian.base.Expression?
function Parser:parse_expression(min_precedence)
  local left = self:parse_prefix()
  if left == nil then
    return nil
  end
  left = self:parse_postfix(left)

  while true do
    local operator = self:current()
    local precedence = operator.kind == "operator" and binary_precedence[operator.value] or nil
    if precedence == nil or precedence < min_precedence then
      break
    end
    self.index = self.index + 1
    local right = self:parse_expression(precedence + 1)
    if right == nil then
      break
    end
    left = {
      kind = "binary",
      operator = operator.value,
      left = left,
      right = right,
      range = { start = left.range.start, finish = right.range.finish },
    }
  end

  return left
end

---Parse a Bases filter or formula expression.
---@param source string
---@return obsidian.base.Expression?
---@return obsidian.base.Diagnostic[]
function M.parse(source)
  local tokens, diagnostics = lex(source)
  local parser = setmetatable({ tokens = tokens, diagnostics = diagnostics, index = 1 }, Parser)
  local expression = parser:parse_expression(1)
  local trailing = parser:current()
  if trailing.kind ~= "eof" then
    diagnostic(
      diagnostics,
      "expression.trailing-token",
      ("unexpected token %q after expression"):format(trailing.raw),
      trailing.start,
      trailing.finish
    )
  end
  return expression, diagnostics
end

M.lex = lex

return M
