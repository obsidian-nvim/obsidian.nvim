local M = require "obsidian.lib.moment"

local new_set = MiniTest.new_set

local function moment_js_format(time, fmt)
  if vim.fn.executable "node" ~= 1 then
    return nil
  end

  local result = vim
    .system({
      "node",
      "-e",
      [[
let moment;
try {
  moment = require("moment");
  moment.locale("en");
} catch (err) {
  process.exit(2);
}
const args = process.argv.slice(-2);
const time = Number(args[0]);
const fmt = args[1];
process.stdout.write(moment.unix(time).format(fmt));
]],
      tostring(time),
      fmt,
    }, { text = true })
    :wait()

  if result.code ~= 0 then
    return nil
  end

  return result.stdout or ""
end

local date = os.time {
  year = 2009,
  month = 2, -- 0-index js
  day = 14,
  hour = 15,
  min = 25,
  sec = 50,
  -- 125 ms is ignored
}

local format_eq = MiniTest.new_expectation(
  -- Expectation subject
  "check format result equals expectation",
  -- Predicate
  function(format, expectation)
    local moment_result = moment_js_format(date, format)
    return M.format(date, format) == expectation and (moment_result == nil or moment_result == expectation)
  end,
  -- Fail context
  function(format, expectation)
    local momentjs_result = moment_js_format(date, format)
    return string.format(
      "Format: %s\nExpectation: %s\nMoment Result: %s\n",
      format,
      expectation,
      momentjs_result == nil and "skipped" or momentjs_result
    )
  end
)

local function timezone_offset(time)
  return os.date("%z", time)
end

local function timezone_offset_colon(time)
  local offset = os.date("%z", time)
  return string.sub(offset, 1, 3) .. ":" .. string.sub(offset, 4, 5)
end

local T = new_set()

T["format using constants"] = function() end

T["format YY"] = function()
  format_eq("YY", "09")
end

T["format LT/LTS"] = function()
  format_eq("LT", "3:25 PM")
  format_eq("LTS", "3:25:50 PM")
end

T["format ordinals"] = function()
  format_eq("Do", "14th")
  format_eq("Wo", "7th")
  format_eq("Qo", "1st")
end

T["format day of year"] = function()
  format_eq("DDD", "45")
  format_eq("DDDD", "045")
end

T["format weekday tokens"] = function()
  format_eq("d", "6")
  format_eq("dd", "Sa")
  format_eq("E", "6")
end

T["format week tokens"] = function()
  format_eq("w", "7")
  format_eq("ww", "07")
  format_eq("W", "7")
  format_eq("WW", "07")
end

T["format quarter"] = function()
  format_eq("Q", "1")
end

T["format iso week year"] = function()
  format_eq("GGGG", "2009")
  format_eq("GG", "09")
end

T["format timezone tokens"] = function()
  format_eq("ZZ", timezone_offset(date))
  format_eq("Z", timezone_offset_colon(date))
end

T["format unix timestamps"] = function()
  format_eq("X", tostring(math.floor(date)))
  format_eq("x", tostring(math.floor(date * 1000)))
end

T["format localized tokens"] = function()
  format_eq("L", "02/14/2009")
  format_eq("LL", "February 14, 2009")
  format_eq("LLL", "February 14, 2009 3:25 PM")
  format_eq("LLLL", "Saturday, February 14, 2009 3:25 PM")
end

T["format escaped localized tokens"] = function()
  format_eq("[LT] LT", "LT 3:25 PM")
  format_eq("[LTS] LTS", "LTS 3:25:50 PM")
end

T["format token precedence"] = function()
  format_eq("MMMMMM", "February02")
end

T["format mixed literals and tokens"] = function()
  format_eq("YYYY[YY]YY", "2009YY09")
  format_eq("[YYYY] YYYY", "YYYY 2009")
end

T["format consecutive tokens"] = function()
  format_eq("DDDDDD", "04514")
  format_eq("HHmmss", "152550")
end

T["format escape brackets"] = function()
  format_eq("[day]", "day") -- Single bracket
  format_eq("[day] YY [YY]", "day 09 YY") -- Double bracket
  format_eq("[YY", "[09") -- Un-ended bracket
  format_eq("[[YY]]", "[YY]") -- Double nested brackets
  format_eq("[[]", "[") -- Escape open bracket
  format_eq("[Last]", "Last") -- Escape open bracket
  format_eq("[L] L", "L 02/14/2009") -- localized tokens with escaped localized tokens
  format_eq("[LLL] LLL", "LLL February 14, 2009 3:25 PM") -- localized tokens with escaped localized tokens (recursion)
  format_eq("[L LL LLL LLLL aLa]", "L LL LLL LLLL aLa") -- localized tokens with escaped localized tokens
  format_eq("YYYY[\n]DD[\n]", "2009\n14\n") -- Newlines
end

return T
