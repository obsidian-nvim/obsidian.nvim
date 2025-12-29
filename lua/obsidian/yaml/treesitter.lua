local M = {}

local ts = vim.treesitter

local get_text = ts.get_node_text

-- handlers per ts node type
local H = {}

setmetatable(H, {
  __index = function(t, k)
    if not rawget(t, k) then
      -- print("unimplemented yaml ts node type", k, "\n")
      return function() end
    end
  end,
})

---@param node TSNode
---@param src string
local parse_node = function(node, src)
  local t = node:type()
  if H[t] then
    return H[t](node, src)
  end
end

---@param index integer 0-indexed
local function index_item(index)
  ---@param node TSNode
  ---@param src string
  return function(node, src)
    local child = node:child(index)
    assert(child)
    return parse_node(child, src)
  end
end

H.document = index_item(0)
H.block_node = index_item(0)
H.flow_node = index_item(0)
H.plain_scalar = index_item(0)
H.block_sequence_item = index_item(1)

---@param node TSNode
---@param src string
H.string_scalar = function(node, src)
  return tostring(get_text(node, src))
end

---@param node TSNode
---@param src string
H.double_quote_scalar = function(node, src)
  return get_text(node, src):sub(2, -2)
end

---@param node TSNode
---@param src string
H.single_quote_scalar = function(node, src)
  return get_text(node, src):sub(2, -2)
end

H.block_scalar = function(node, src)
  local text = get_text(node, src)
  text = text:sub(2)
  return vim.trim(text)
  -- local ret = {}
  --
  -- for line in vim.gsplit(text, "\n") do
  --   ret[#ret + 1] = vim.trim(line)
  -- end
  -- return vim.trim(table.concat(ret, "\n"))
end

---@param node TSNode
---@param src string
H.boolean_scalar = function(node, src)
  local text = get_text(node, src)
  if text == "true" then
    return true
  elseif text == "false" then
    return false
  else
    error "wrong boolean"
  end
end

H.null_scalar = function()
  return vim.NIL
end

---@param node TSNode
---@param src string
H.float_scalar = function(node, src)
  local text = get_text(node, src)
  return tonumber(text)
end

---@param node TSNode
---@param src string
H.integer_scalar = function(node, src)
  local text = get_text(node, src)
  return tonumber(text)
end

---@param node TSNode
---@param src string
local get_sequence = function(node, src)
  local seq = {}
  for child in node:iter_children() do
    seq[#seq + 1] = parse_node(child, src)
  end
  return seq
end

H.flow_sequence = get_sequence
H.block_sequence = get_sequence

---@param node TSNode
---@param src string
local get_mapping = function(node, src)
  local mapping = {}
  for child in node:iter_children() do
    local t = child:type()
    if t == "block_mapping_pair" or t == "flow_pair" then
      local k_child = child:child(0)
      local v_child = child:child(2)
      if k_child and v_child then
        local k = parse_node(k_child, src)
        local v = parse_node(v_child, src)
        mapping[k] = v
      elseif k_child then
        local k = parse_node(k_child, src)
        mapping[k] = vim.NIL
      end
    end
  end
  return mapping
end

H.block_mapping = get_mapping
H.flow_mapping = get_mapping

M.loads = function(str)
  local parser = ts.get_string_parser(str, "yaml", {})
  local tree = parser:parse()[1]
  local root = tree:root()

  -- local log = require "obsidian.log"
  -- if root:has_error() then
  -- log.warn("treesitter err: ", str)
  -- end

  local doc = root:child(0)
  assert(doc, "empty yaml body")
  return H[doc:type()](doc, str)
end

M.name = "treesitter"

return M
