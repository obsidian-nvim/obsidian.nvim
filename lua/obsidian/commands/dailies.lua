local daily = require "obsidian.daily"

---@param arg string
---@return integer
local function parse_offset(arg)
  assert(arg:match "^[+-]?%d+$", string.format("invalid offset '%s'", arg))
  local offset = assert(tonumber(arg))
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
      offset_start = math.min(0, offset)
      offset_end = math.max(0, offset)
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
    note:open { write_if_missing = true }
  end)
end
