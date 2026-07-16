local cache = require "obsidian.cache"
local completion = require "obsidian.completion.frontmatter"
local yaml = require "obsidian.yaml"

local M = {}

---@type lsp.CompletionList
local EMPTY_RESPONSE = {
  isIncomplete = true,
  items = {},
}

---@param value any
---@return string?, string?
local function scalar(value)
  local value_type = type(value)
  if value_type ~= "string" and value_type ~= "number" and value_type ~= "boolean" then
    return nil, nil
  end

  local text = yaml.dumps(value)
  -- A leading # starts a YAML comment and must be quoted as a scalar.
  if value_type == "string" and vim.startswith(text, "#") then
    text = vim.json.encode(value)
  end
  if text:find("\n", 1, true) then
    return nil, nil
  end
  return tostring(value), text
end

---@param values table<string, { label: string, text: string, count: integer }>
---@param value any
local function add_value(values, value)
  if type(value) == "table" and vim.islist(value) then
    for _, item in ipairs(value) do
      add_value(values, item)
    end
    return
  end

  local label, text = scalar(value)
  if not label or not text then
    return
  end
  local id = type(value) .. "\0" .. text
  local entry = values[id]
  if entry then
    entry.count = entry.count + 1
  else
    values[id] = { label = label, text = text, count = 1 }
  end
end

---@param term string
---@param candidate string
---@return boolean
local function matches(term, candidate)
  return candidate:lower():find(term:lower(), 1, true) ~= nil
end

---@param callback fun(resp: lsp.CompletionList)
---@param request obsidian.completion.Request
function M.process_completion(callback, request)
  local context = completion.context(request)
  if not context or #context.term < Obsidian.opts.completion.min_chars or not cache.is_enabled() then
    callback(EMPTY_RESPONSE)
    return
  end

  cache.when_ready(function()
    if not cache.is_enabled() then
      callback(EMPTY_RESPONSE)
      return
    end

    local ok, rows = pcall(cache.notes.all)
    if not ok then
      callback(EMPTY_RESPONSE)
      return
    end

    local items = {}
    if context.kind == "key" then
      local keys = {}
      for _, row in pairs(rows) do
        for key in pairs(row.properties or {}) do
          key = tostring(key)
          keys[key] = (keys[key] or 0) + 1
        end
      end

      for key, count in pairs(keys) do
        if matches(context.term, key) then
          items[#items + 1] = {
            label = key,
            kind = vim.lsp.protocol.CompletionItemKind.Property,
            filterText = key,
            sortText = string.format("%09d:%s", 999999999 - count, key),
            documentation = {
              kind = "markdown",
              value = string.format("`%s` — used in %d note%s", key, count, count == 1 and "" or "s"),
            },
            textEdit = {
              newText = context.add_colon and key .. ": " or key,
              range = {
                start = { line = request.line, character = context.insert_start },
                ["end"] = { line = request.line, character = context.insert_end },
              },
            },
          }
        end
      end
    else
      local values = {}
      local key = assert(context.key, "frontmatter value completion requires a property key")
      for _, row in pairs(rows) do
        local properties = row.properties or {}
        if properties[key] ~= nil then
          add_value(values, properties[key])
        end
      end

      for _, value in pairs(values) do
        if matches(context.term, value.label) then
          items[#items + 1] = {
            label = value.label,
            kind = vim.lsp.protocol.CompletionItemKind.Value,
            filterText = value.label,
            sortText = string.format("%09d:%s", 999999999 - value.count, value.label),
            documentation = {
              kind = "markdown",
              value = string.format(
                "`%s: %s` — used %d time%s",
                key,
                value.text,
                value.count,
                value.count == 1 and "" or "s"
              ),
            },
            textEdit = {
              newText = value.text,
              range = {
                start = { line = request.line, character = context.insert_start },
                ["end"] = { line = request.line, character = context.insert_end },
              },
            },
          }
        end
      end
    end

    callback {
      isIncomplete = true,
      items = items,
    }
  end)
end

return M
