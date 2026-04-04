local MiniTest = require "mini.test"
local eq = MiniTest.expect.equality
local h = dofile "tests/helpers.lua"

local T, child = h.child_vault {
  pre_case = [[
    Obsidian.opts.footer.enabled = true
    Obsidian.opts.footer.separator = false
    Obsidian.opts.statusline.enabled = false
    vim.g.obsidian_footer_update_interval = 1000000
  ]],
}

local function get_footer_lines()
  return child.lua [[
    local ns = vim.api.nvim_get_namespaces()["obsidian.footer"]
    local marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
    local lines = {}

    for _, mark in ipairs(marks) do
      local details = mark[4]
      local virt_lines = details and details.virt_lines or {}
      for _, chunks in ipairs(virt_lines) do
        local text = ""
        for _, chunk in ipairs(chunks) do
          text = text .. chunk[1]
        end
        lines[#lines + 1] = text
      end
    end

    return lines
  ]]
end

local function start_and_wait_for_footer()
  child.lua [[
    require("obsidian.footer").start(0)
    vim.wait(500, function()
      return vim.b.obsidian_status ~= nil
    end)
  ]]
end

T["format supports newlines"] = function()
  local root = child.Obsidian.dir
  h.write("hello", root / "note.md")

  child.lua [[
    Obsidian.opts.footer.format = "first line\nsecond line"
  ]]
  child.cmd("edit " .. tostring(root / "note.md"))
  start_and_wait_for_footer()

  eq({ "first line", "second line" }, get_footer_lines())
end

T["format supports custom substitutions"] = function()
  local root = child.Obsidian.dir
  h.write("hello world", root / "note.md")

  child.lua [[
    Obsidian.opts.footer.substitutions = {
      computed = function(note)
        return string.format("%s:%d", note.id, note:status().words)
      end,
    }
    Obsidian.opts.footer.format = "{{computed}}"
  ]]

  child.cmd("edit " .. tostring(root / "note.md"))
  start_and_wait_for_footer()

  local footer_lines = get_footer_lines()
  eq(1, #footer_lines)
  eq(true, footer_lines[1]:match "^note:%d+$" ~= nil)
end

T["lined_metsions renders linked mentions lines"] = function()
  local root = child.Obsidian.dir
  h.write("target body", root / "target.md")
  h.write("[[target]]\n[target](target.md)", root / "source.md")

  child.lua [[
    Obsidian.opts.footer.format = "{{linked_mentions}}"
  ]]

  child.cmd("edit " .. tostring(root / "target.md"))
  start_and_wait_for_footer()

  local footer_lines = get_footer_lines()
  eq(true, vim.tbl_contains(footer_lines, "source.md: [[target]]"))
  eq(true, vim.tbl_contains(footer_lines, "source.md: [target](target.md)"))
end

T["linked_mentions token is supported"] = function()
  local root = child.Obsidian.dir
  h.write("target body", root / "target.md")
  h.write("[[target]]", root / "b_source.md")
  h.write("[[target]]\n[target](target.md)", root / "a_source.md")

  child.lua [[
    Obsidian.opts.footer.format = "{{linked_mentions}}"
  ]]

  child.cmd("edit " .. tostring(root / "target.md"))
  start_and_wait_for_footer()

  local footer_lines = get_footer_lines()
  eq("Linked Mentions", footer_lines[1])
  eq("", footer_lines[2])
  eq("a_source.md: [[target]]", footer_lines[3])
  eq("a_source.md: [target](target.md)", footer_lines[4])
  eq("b_source.md: [[target]]", footer_lines[5])
end

T["linked_mentions renders nothing when empty"] = function()
  local root = child.Obsidian.dir
  h.write("target body", root / "target.md")

  child.lua [[
    Obsidian.opts.footer.format = "{{linked_mentions}}"
  ]]

  child.cmd("edit " .. tostring(root / "target.md"))
  start_and_wait_for_footer()

  eq({}, get_footer_lines())
end

T["status substitution preserves legacy status text"] = function()
  local root = child.Obsidian.dir
  h.write("hello world", root / "note.md")

  child.lua [[
    Obsidian.opts.footer.format = "{{status}}"
  ]]

  child.cmd("edit " .. tostring(root / "note.md"))
  start_and_wait_for_footer()

  local footer_lines = get_footer_lines()
  eq(1, #footer_lines)
  eq(true, footer_lines[1]:match "^%d+ backlinks  %d+ properties  %d+ words  %d+ chars$" ~= nil)
end

return T
