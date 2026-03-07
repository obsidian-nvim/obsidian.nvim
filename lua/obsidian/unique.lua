local moment = require "obsidian.lib.moment"
local Note = require "obsidian.note"
local api = require "obsidian.api"

local M = {}

--- Token patterns ordered from smallest to largest time unit.
--- The first match determines the increment unit.
---@type {pattern: string, field: string}[]
local TOKEN_UNITS = {
  -- Seconds (smallest unit)
  { pattern = "ss", field = "sec" },
  { pattern = "s", field = "sec" },
  -- Minutes
  { pattern = "mm", field = "min" },
  { pattern = "m", field = "min" },
  -- Hours
  { pattern = "HH", field = "hour" },
  { pattern = "hh", field = "hour" },
  { pattern = "H", field = "hour" },
  { pattern = "h", field = "hour" },
  -- Days
  { pattern = "DDDD", field = "day" },
  { pattern = "DDD", field = "day" },
  { pattern = "DD", field = "day" },
  { pattern = "Do", field = "day" },
  { pattern = "D", field = "day" },
  -- Months
  { pattern = "MMMM", field = "month" },
  { pattern = "MMM", field = "month" },
  { pattern = "MM", field = "month" },
  { pattern = "M", field = "month" },
  -- Years (largest unit)
  { pattern = "YYYY", field = "year" },
  { pattern = "GGGG", field = "year" },
  { pattern = "YY", field = "year" },
  { pattern = "GG", field = "year" },
}

--- Get the smallest time unit present in a moment.js format string.
---@param fmt string The format string (e.g., "YYYYMMDDHHmm")
---@return string field The date field to increment ("sec", "min", "hour", "day", "month", "year")
local function get_smallest_unit(fmt)
  for _, token in ipairs(TOKEN_UNITS) do
    if fmt:find(token.pattern) then
      return token.field
    end
  end
  return "day" -- fallback
end

--- Increment a timestamp by the smallest unit present in the format.
---@param timestamp integer Unix timestamp
---@param fmt string The format string
---@return integer new_timestamp
local function increment_timestamp(timestamp, fmt)
  local unit = get_smallest_unit(fmt)
  local date = os.date("*t", timestamp)
  date[unit] = date[unit] + 1
  return os.time(date)
end

--- Generate a unique note ID, handling collisions by incrementing timestamp.
--- When a collision is detected, the timestamp is incremented by the smallest
--- time unit present in the format (matching Obsidian app behavior).
---
---@param timestamp integer|nil Unix timestamp (defaults to os.time())
---@param fmt string The format string (e.g., "YYYYMMDDHHmm")
---@param existing_stems table<string, boolean> Map of existing file stems
---@return string id The unique note ID
---@return integer timestamp The final timestamp used
local function generate_unique_id(timestamp, fmt, existing_stems)
  timestamp = timestamp or os.time()
  local date_id = moment.format(timestamp, fmt)

  while existing_stems[date_id] do
    timestamp = increment_timestamp(timestamp, fmt)
    date_id = moment.format(timestamp, fmt)
  end

  return date_id, timestamp
end

---@param timestamp integer?
---@return string? A unique note ID based on the timestamp and format, ensuring no collisions with existing
function M.new_unique_id(timestamp)
  timestamp = timestamp or os.time()

  local unique_note_folder = Obsidian.opts.unique_note.folder
  local folder_path = unique_note_folder and Obsidian.dir / unique_note_folder or Obsidian.dir

  if folder_path:is_dir() == false then
    local choice =
      api.confirm("Unique note folder does not exist: \n" .. tostring(folder_path) .. "\n" .. "Crete it now?")

    if choice == "Yes" then
      folder_path:mkdir()
    else
      return
    end
  end

  -- Collect existing file stems to check for collisions
  local existing_stems = {}
  for file, t in vim.fs.dir(tostring(folder_path)) do
    if t == "file" then
      local stem = file:gsub("%.%w+$", "")
      existing_stems[stem] = true
    end
  end

  -- Generate unique ID with collision handling (increments timestamp by smallest unit)
  ---@diagnostic disable-next-line: param-type-mismatch
  local date_id = generate_unique_id(timestamp, Obsidian.opts.unique_note.format, existing_stems)

  return date_id
end

---@param timestamp integer?
---@return obsidian.Note? A new unique note instance with a unique ID based on the timestamp and format.
function M.new_unique_note(timestamp)
  local unique_id = M.new_unique_id(timestamp)
  if not unique_id then
    return
  end

  local note = Note.create {
    id = unique_id,
    template = Obsidian.opts.unique_note.template,
    dir = Obsidian.opts.unique_note.folder,
    verbatim = true,
    should_write = true,
  }
  return note
end

---@param timestamp integer?
---@return string? A wiki link to the unique note (e.g., "[[20240615]]")
function M.new_unique_link(timestamp)
  local unique_id = M.new_unique_id(timestamp)
  -- NOTE: only do wiki link because obsidian app only do wiki link regardless of link style, and there's no valid alias for unique note
  if not unique_id then
    return
  end
  return "[[" .. unique_id .. "]]"
end

return M
