local M = require "obsidian.util"

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["is_hex_color"] = new_set()

T["is_hex_color"]["recognizes valid hex colors"] = function()
  eq(M.is_hex_color "#abc", true)
  eq(M.is_hex_color "#abcd", true)
  eq(M.is_hex_color "#aabbcc", true)
  eq(M.is_hex_color "#aabbccdd", true)
end

T["is_hex_color"]["rejects invalid hex colors"] = function()
  eq(M.is_hex_color "#ab", false)
  eq(M.is_hex_color "#abcde", false)
  eq(M.is_hex_color "#aabbccfg", false)
  eq(M.is_hex_color "#aabbccdde", false)
end

T["is_hex_color"]["rejects invalid chars"] = function()
  eq(M.is_hex_color "#ggg", false)
  eq(M.is_hex_color "#12345z", false)
  eq(M.is_hex_color "#xyzxyz", false)
end

return T
