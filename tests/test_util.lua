local M = require "obsidian.util"
local picker_util = require "obsidian.picker.util"
local compat = require "obsidian.compat"
local Path = require "obsidian.path"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["preview_path"] = new_set()

T["preview_path"]["lists directory contents and marks folders"] = function()
  local dir = Path.temp { suffix = "-obsidian-preview" }
  dir:mkdir { parents = true }
  local folder = dir / "folder1"
  folder:mkdir()
  M.write_file(tostring(dir / "file1.md"), "# file1")
  M.write_file(tostring(dir / "file2.lua"), "return {}")

  local preview = picker_util.preview_path(dir)
  eq({ "file1.md", "file2.lua", "folder1/" }, vim.api.nvim_buf_get_lines(preview.buf, 0, -1, false))
  eq("wipe", vim.bo[preview.buf].bufhidden)

  vim.api.nvim_buf_delete(preview.buf, { force = true })
  vim.fn.delete(tostring(dir), "rf")
end

T["list_unique"] = function()
  eq({ "hi", "hey" }, compat.list_unique { "hi", "hey", "hi", "hi" })
end

T["filename validation distinguishes filesystem and link restrictions"] = function()
  eq(false, M.is_valid_filename "bad:name")
  eq(true, M.is_valid_filename "has#fragment-marker")
  eq(true, M.contains_invalid_characters "has#fragment-marker")
  eq(false, M.contains_invalid_characters "bad:name")
end

T["match_case"] = new_set()

T["match_case"]["should match case of key to prefix"] = function()
  eq(M.match_case("Foo", "foo"), "Foo")
  eq(M.match_case("In-cont", "in-context learning"), "In-context learning")
end

T["is_whitespace"] = function()
  eq(true, M.is_whitespace "  ")
  eq(false, M.is_whitespace "a  ")
end

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

T["count_indent"] = new_set()

T["count_indent"]["should count each space as one indent"] = function()
  eq(2, M.count_indent "  ")
end

T["count_indent"]["should count each tab as one indent"] = function()
  eq(2, M.count_indent "\t\t")
end

T["strip"] = new_set()

T["strip"]["left whitespace"] = new_set()

T["strip"]["left whitespace"]["should strip tabs and spaces from left end only"] = function()
  eq("foo ", M.lstrip_whitespace "\tfoo ")
end

T["strip"]["left whitespace"]["should respect the limit parameters"] = function()
  eq(" foo ", M.lstrip_whitespace("  foo ", 1))
end

return T
