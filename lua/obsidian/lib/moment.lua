return {
  format = require "obsidian.lib.moment.format",
  parse = require "obsidian.lib.moment.parse",
  to_timestamp = function(date_table)
    -- Convert date table to timestamp using os.time
    -- The date_table should have year, month, day, hour, min, sec, isdst fields
    return os.time(date_table)
  end,
}
