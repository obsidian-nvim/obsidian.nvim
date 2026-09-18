local daily = require "obsidian.daily"

---@param arg string
---@return integer
local function parse_offset(arg)
  local offset
  if vim.startswith(arg, "+") then
    offset = tonumber(string.sub(arg, 2))
  elseif vim.startswith(arg, "-") then
    offset = -(tonumber(string.sub(arg, 2)) or error(string.format("invalid offset '%s'", arg)))
  else
    offset = tonumber(arg)
  end
  assert(offset, string.format("invalid offset '%s'", arg))
  ---@cast offset integer
  return offset
end

---@param data obsidian.CommandArgs
return function(data)
  ---@type integer
  local offset_start = -5
  ---@type integer
  local offset_end = 0

  if data.fargs and #data.fargs > 0 then
    if #data.fargs == 1 then
      local offset = parse_offset(data.fargs[1])
      if offset >= 0 then
        offset_end = offset
      else
        offset_start = offset
      end
    elseif #data.fargs == 2 then
      local offsets = vim.tbl_map(parse_offset, data.fargs)
      table.sort(offsets)
      offset_start = offsets[1]
      offset_end = offsets[2]
    else
      error ":Obsidian dailies expected at most 2 arguments"
    end
  end

  ---@cast offset_start integer
  ---@cast offset_end integer
  daily.pick(offset_start, offset_end, function(note)
    if not note:exists() then
      note:write()
    end
    note:open()
  end)
end
