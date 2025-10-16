local log = require "obsidian.log"
local weekly = require "obsidian.weekly"

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
      error ":Obsidian weeklies expected at most 2 arguments"
    end
  end

  local picker = Obsidian.picker
  if not picker then
    log.err "No picker configured"
    return
  end

  ---@type obsidian.PickerEntry[]
  local weeklies = {}
  for offset = offset_end, offset_start, -1 do
    local datetime = os.time() + (offset * 7 * 24 * 60 * 60)
    local weekly_note_path = weekly.weekly_note_path(datetime)
    local weekly_note_alias = tostring(os.date(Obsidian.opts.weekly_notes.alias_format or "Week %V, %Y", datetime))
    if offset == 0 then
      weekly_note_alias = weekly_note_alias .. " @this-week"
    elseif offset == -1 then
      weekly_note_alias = weekly_note_alias .. " @last-week"
    elseif offset == 1 then
      weekly_note_alias = weekly_note_alias .. " @next-week"
    end
    if not weekly_note_path:is_file() then
      weekly_note_alias = weekly_note_alias .. " ➡️ create"
    end
    weeklies[#weeklies + 1] = {
      value = offset,
      display = weekly_note_alias,
      ordinal = weekly_note_alias,
      filename = tostring(weekly_note_path),
    }
  end

  picker:pick(weeklies, {
    prompt_title = "Weeklies",
    callback = function(entry)
      local note = weekly.weekly(entry.value, {})
      note:open()
    end,
  })
end
