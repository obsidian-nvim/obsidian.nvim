local M = {}

local ts = require "vim.treesitter"

local MATH_NODES = {
  displayed_equation = true,
  inline_formula = true,
  math_environment = true,
}

local TEXT_NODES = {
  text_mode = true,
  label_definition = true,
  label_reference = true,
}

local CODE_BLOCK_NODES = {
  fenced_code_block = true,
  indented_code_block = true,
}

function M.in_text(check_parent)
  local node = ts.get_node { ignore_injections = false }
  while node do
    local node_type = node:type()
    -- if in code block, always consider it as text
    if CODE_BLOCK_NODES[node_type] then
      return true
    end
    if node_type == "text_mode" then
      if check_parent then
        local parent = node:parent()
        if parent and MATH_NODES[parent:type()] then
          return false
        end
      end
      return true
    end
    if MATH_NODES[node_type] then
      return false
    end
    node = node:parent()
  end
  return true
end

function M.in_mathzone()
  local node = ts.get_node { ignore_injections = false }
  while node do
    local node_type = node:type()
    -- if in code block, don't consider it math.
    if CODE_BLOCK_NODES[node_type] then
      return false
    end
    if TEXT_NODES[node_type] then
      return false
    end
    if MATH_NODES[node_type] then
      return true
    end
    node = node:parent()
  end
  return false
end

return M
