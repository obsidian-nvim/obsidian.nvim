local eq = MiniTest.expect.equality

local h = dofile "tests/helpers.lua"

local T, child = h.child_vault()

T["quick switch"] = MiniTest.new_set()

T["quick switch"]["passes config to find notes"] = function()
  local captured = child.lua [[
local captured
local original = Obsidian.picker.find_notes
Obsidian.opts.quick_switch.show_existing_only = false
Obsidian.opts.quick_switch.show_attachments = true
Obsidian.picker.find_notes = function(opts)
  captured = opts
end
require "obsidian.commands.quick_switch" { args = "foo" }
Obsidian.picker.find_notes = original
return captured
  ]]

  eq("Quick Switch", captured.prompt_title)
  eq("foo", captured.query)
  eq(false, captured.show_existing_only)
  eq(true, captured.show_attachments)
end

T["quick switch"]["find notes passes options to find files"] = function()
  local captured = child.lua [[
local picker = require "obsidian.picker"
local captured
local original = picker.find_files
picker.find_files = function(opts)
  captured = opts
end
picker.find_notes {
  no_default_mappings = true,
  show_existing_only = false,
  show_attachments = true,
}
picker.find_files = original
return captured
  ]]

  eq(false, captured.show_existing_only)
  eq(true, captured.show_attachments)
  eq(true, captured.use_cache)
end

T["quick switch"]["cache picker filters attachments and missing links"] = function()
  h.child_mock_vault_contents(child, {
    ["Note.md"] = "# Note\n[[Missing]]\n![[Image.png]]\n![[Missing.pdf]]\nA [[Missing|label]]",
    ["Image.png"] = "attachment",
  })
  h.child_setup_cache(child)

  local result = child.lua [[
local picker = require "obsidian.picker"
local cache = require "obsidian.cache"
local icons = require "obsidian.icons"
local original_select = picker.select
local snapshots = {}
local pick_opts
local selected_entries
local on_choice

local function seen(values)
  local out = {}
  for _, entry in ipairs(values) do
    out[entry.text] = true
  end
  return out
end

local function user_data_by_text(values)
  local out = {}
  for _, entry in ipairs(values) do
    out[entry.text] = entry.user_data
  end
  return out
end

picker.select = function(values, opts, callback)
  pick_opts = opts
  on_choice = callback
  if #snapshots < 2 then
    snapshots[#snapshots + 1] = seen(values)
  else
    snapshots[#snapshots + 1] = user_data_by_text(values)
    selected_entries = values
  end
end

cache.find_files { use_cache = true }
cache.find_files { use_cache = true, show_existing_only = false }
cache.find_files { use_cache = true, show_existing_only = false, show_attachments = true }

local formatted_missing = pick_opts.format_item {
  text = "Missing",
  user_data = { missing = true },
}
local formatted_image = pick_opts.format_item {
  text = "Image.png",
  filename = "Image.png",
  user_data = { attachment = true },
}

local function find_entry(text)
  for _, entry in ipairs(selected_entries) do
    if entry.text == text then
      return entry
    end
  end
end

local missing_preview = pick_opts.preview_item(find_entry "Missing")
local existing_preview = pick_opts.preview_item(find_entry "Note")
local missing_preview_lines = vim.api.nvim_buf_get_lines(missing_preview.buf, 0, -1, false)
local existing_preview_lines = vim.api.nvim_buf_get_lines(existing_preview.buf, 0, -1, false)

local actions = require "obsidian.actions"
local attachment = require "obsidian.attachment"
local original_add_attachment = actions.add_attachment
local captured_add_attachment
local expected_missing_attachment_path = attachment.resolve_attachment_path(
  "Missing.pdf",
  vim.fs.joinpath(tostring(Obsidian.dir), "Note.md")
)
actions.add_attachment = function(src, opts)
  captured_add_attachment = { src = src, opts = opts }
end
on_choice {
  {
  text = "Missing.pdf",
  filename = expected_missing_attachment_path,
  user_data = { attachment = true, missing = true },
  },
}
actions.add_attachment = original_add_attachment
picker.select = original_select

return {
  default_seen = snapshots[1],
  missing_seen = snapshots[2],
  attachment_seen = snapshots[3],
  formatted_missing = formatted_missing,
  formatted_image = formatted_image,
  expected_missing = icons.get_icon { user_data = { missing = true } } .. " Missing",
  expected_image = icons.get_icon { filename = "Image.png" } .. " Image.png",
  captured_add_attachment = captured_add_attachment,
  expected_missing_attachment_path = expected_missing_attachment_path,
  missing_preview_lines = missing_preview_lines,
  missing_preview_filetype = vim.bo[missing_preview.buf].filetype,
  missing_preview_bufhidden = vim.bo[missing_preview.buf].bufhidden,
  existing_preview_lines = existing_preview_lines,
  existing_preview_filetype = vim.bo[existing_preview.buf].filetype,
}
  ]]

  eq(true, result.default_seen["Note"])
  eq(nil, result.default_seen["Image.png"])
  eq(nil, result.default_seen["Missing"])
  eq(nil, result.default_seen["Missing.pdf"])

  eq(true, result.missing_seen["Note"])
  eq(true, result.missing_seen["Missing"])
  eq(nil, result.missing_seen["Image.png"])
  eq(nil, result.missing_seen["Missing.pdf"])

  eq({ attachment = false, missing = false }, result.attachment_seen["Note"])
  eq(false, result.attachment_seen["Missing"].attachment)
  eq(true, result.attachment_seen["Missing"].missing)
  eq(2, #result.attachment_seen["Missing"].references)
  eq({ attachment = true, missing = false }, result.attachment_seen["Image.png"])
  eq(true, result.attachment_seen["Missing.pdf"].attachment)
  eq(true, result.attachment_seen["Missing.pdf"].missing)
  eq(result.expected_missing, result.formatted_missing)
  eq(result.expected_image, result.formatted_image)
  eq(nil, result.captured_add_attachment.src)
  eq(false, result.captured_add_attachment.opts.insert)
  eq(result.expected_missing_attachment_path, result.captured_add_attachment.opts.dst)
  eq({
    "Note.md:2:1",
    "",
    "```markdown",
    "[[Missing]]",
    "```",
    "",
    "Note.md:5:3",
    "",
    "```markdown",
    "[[Missing|label]]",
    "```",
  }, result.missing_preview_lines)
  eq("markdown", result.missing_preview_filetype)
  eq("wipe", result.missing_preview_bufhidden)
  eq({
    "# Note",
    "[[Missing]]",
    "![[Image.png]]",
    "![[Missing.pdf]]",
    "A [[Missing|label]]",
  }, result.existing_preview_lines)
  eq("markdown", result.existing_preview_filetype)
end

return T
