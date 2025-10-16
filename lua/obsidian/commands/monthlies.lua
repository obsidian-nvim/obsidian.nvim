local log = require "obsidian.log"
local monthly = require "obsidian.monthly"

---@param arg string
---@return number
local function parse_offset(arg)
  if vim.startswith(arg, "+") then
    return assert(tonumber(string.sub(arg, 2)), string.format("invalid offset '%s'", arg))
  elseif vim.startswith(arg, "-") then
    return -assert(tonumber(string.sub(arg, 2)), string.format("invalid offset '%s'", arg))
  else
    return assert(tonumber(arg), string.format("invalid offset '%s'", arg))
  end
end

---@param data obsidian.CommandArgs
return function(data)
  local offset_start = -5
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
      error ":Obsidian monthlies expected at most 2 arguments"
    end
  end

  local picker = Obsidian.picker
  if not picker then
    log.err "No picker configured"
    return
  end

  ---@type obsidian.PickerEntry[]
  local monthlies = {}
  for offset = offset_end, offset_start, -1 do
    local now = os.time()
    local year = tonumber(os.date("%Y", now))
    local month = tonumber(os.date("%m", now))

    -- Calculate target month
    month = month + offset
    while month > 12 do
      month = month - 12
      year = year + 1
    end
    while month < 1 do
      month = month + 12
      year = year - 1
    end

    local datetime = os.time { year = year, month = month, day = 1, hour = 0, min = 0, sec = 0 }
    local monthly_note_path = monthly.monthly_note_path(datetime)
    local monthly_note_alias = tostring(os.date(Obsidian.opts.monthly_notes.alias_format or "%B %Y", datetime))
    if offset == 0 then
      monthly_note_alias = monthly_note_alias .. " @this-month"
    elseif offset == -1 then
      monthly_note_alias = monthly_note_alias .. " @last-month"
    elseif offset == 1 then
      monthly_note_alias = monthly_note_alias .. " @next-month"
    end
    if not monthly_note_path:is_file() then
      monthly_note_alias = monthly_note_alias .. " ➡️ create"
    end
    monthlies[#monthlies + 1] = {
      value = offset,
      display = monthly_note_alias,
      ordinal = monthly_note_alias,
      filename = tostring(monthly_note_path),
    }
  end

  picker:pick(monthlies, {
    prompt_title = "Monthlies",
    callback = function(entry)
      local note = monthly.monthly(entry.value, {})
      note:open()
    end,
  })
end
