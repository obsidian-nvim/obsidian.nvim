local log = require "obsidian.log"
local quarterly = require "obsidian.quarterly"

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
  local offset_start = -3
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
      error ":Obsidian quarterlies expected at most 2 arguments"
    end
  end

  local picker = Obsidian.picker
  if not picker then
    log.err "No picker configured"
    return
  end

  ---@type obsidian.PickerEntry[]
  local quarterlies = {}
  for offset = offset_end, offset_start, -1 do
    local now = os.time()
    local year = tonumber(os.date("%Y", now))
    local month = tonumber(os.date("%m", now))

    -- Calculate target quarter
    month = month + (offset * 3)
    while month > 12 do
      month = month - 12
      year = year + 1
    end
    while month < 1 do
      month = month + 12
      year = year - 1
    end

    local datetime = os.time { year = year, month = month, day = 1, hour = 0, min = 0, sec = 0 }
    local quarterly_note_path = quarterly.quarterly_note_path(datetime)

    -- Calculate quarter number
    local target_month = tonumber(os.date("%m", datetime))
    local quarter = math.floor((target_month - 1) / 3) + 1
    local alias_format = Obsidian.opts.quarterly_notes.alias_format or "Q%q %Y"
    local quarterly_note_alias = alias_format:gsub("%%q", tostring(quarter))
    quarterly_note_alias = os.date(quarterly_note_alias, datetime)

    if offset == 0 then
      quarterly_note_alias = quarterly_note_alias .. " @this-quarter"
    elseif offset == -1 then
      quarterly_note_alias = quarterly_note_alias .. " @last-quarter"
    elseif offset == 1 then
      quarterly_note_alias = quarterly_note_alias .. " @next-quarter"
    end
    if not quarterly_note_path:is_file() then
      quarterly_note_alias = quarterly_note_alias .. " ➡️ create"
    end
    quarterlies[#quarterlies + 1] = {
      value = offset,
      display = quarterly_note_alias,
      ordinal = quarterly_note_alias,
      filename = tostring(quarterly_note_path),
    }
  end

  picker:pick(quarterlies, {
    prompt_title = "Quarterlies",
    callback = function(entry)
      local note = quarterly.quarterly(entry.value, {})
      note:open()
    end,
  })
end
