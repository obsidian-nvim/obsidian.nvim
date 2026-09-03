local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

local function setup_cache()
  child.lua [[require("obsidian.cache").setup { enabled = true, backend = "memory" }]]
  h.child_wait(child, [[return require("obsidian.cache").is_ready()]], { desc = "cache ready" })
end

local function run_inline_completion(line, character)
  return h.child_await(
    child,
    ([[
      require("obsidian.lsp.handlers.inline_completion")({
        textDocument = { uri = vim.uri_from_bufnr(0) },
        position = { line = %d, character = %d },
        context = { triggerKind = 2 },
      }, function(_, result)
        done(result)
      end)
    ]]):format(line, character),
    { desc = "inline completion response" }
  )
end

local function item(insert_text, query, start_col, end_col)
  return {
    insertText = insert_text,
    filterText = query,
    range = {
      start = { line = 0, character = start_col },
      ["end"] = { line = 0, character = end_col },
    },
  }
end

T["offers plain and linked note symbols"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "# test",
    ["writing.md"] = "tes",
  })
  setup_cache()
  child.cmd("edit " .. files["writing.md"])

  eq({ item("test", "tes", 0, 3), item("[[test]]", "tes", 0, 3) }, run_inline_completion(0, 3))
end

T["offers a link when the plain symbol is already complete"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "# test",
    ["writing.md"] = "a test",
  })
  setup_cache()
  child.cmd("edit " .. files["writing.md"])

  eq({ item("[[test]]", "test", 2, 6) }, run_inline_completion(0, 6))
end

T["does not overlap explicit link and tag completion"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "# test",
    ["writing.md"] = "[[tes\n#tes\n#topic/tes",
  })
  setup_cache()
  child.cmd("edit " .. files["writing.md"])

  eq({}, run_inline_completion(0, 5))
  eq({}, run_inline_completion(1, 4))
  eq({}, run_inline_completion(2, 10))
end

return T
