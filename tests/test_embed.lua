local embed = require "obsidian.embed"
local helpers = require "tests.helpers"
local Path = require "obsidian.path"

local eq = MiniTest.expect.equality
local T = MiniTest.new_set()

local function setup_vault()
  local root = Path.temp { suffix = "-obsidian-embed" }
  root:mkdir { parents = true }
  Obsidian = {
    dir = root,
    opts = vim.deepcopy(require "obsidian.config.default"),
  }
  return root
end

local function virtual_text(bufnr)
  local marks =
    vim.api.nvim_buf_get_extmarks(bufnr, vim.api.nvim_create_namespace(embed.NAMESPACE), 0, -1, { details = true })
  local lines = {}
  for _, mark in ipairs(marks) do
    for _, line in ipairs(mark[4].virt_lines or {}) do
      lines[#lines + 1] = line[1][1]
    end
  end
  return lines
end

T["renders a Markdown note without frontmatter"] = function()
  local root = setup_vault()
  helpers.write("---\ntags: [hidden]\n---\n# Included\nBody", root / "Target.md")

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, tostring(root / "Source.md"))
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "![[Target]]" })

  embed.update(bufnr)
  eq({ "# Included", "Body" }, virtual_text(bufnr))
end

T["renders heading and block embeds"] = function()
  local root = setup_vault()
  helpers.write("# First\nOne\n\n## Child\nTwo\n\n# Last\nParagraph ^block", root / "Target.md")

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, tostring(root / "Source.md"))
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "![[Target.md#First]]",
    "![[Target.md#^block]]",
  })

  embed.update(bufnr)
  eq({
    "# First",
    "One",
    "",
    "## Child",
    "Two",
    "Paragraph ^block",
  }, virtual_text(bufnr))
end

T["ignores embeds in fenced code"] = function()
  local root = setup_vault()
  helpers.write("Body", root / "Target.md")

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, tostring(root / "Source.md"))
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "```md", "![[Target.md]]", "```" })

  embed.update(bufnr)
  eq({}, virtual_text(bufnr))
end

return T
