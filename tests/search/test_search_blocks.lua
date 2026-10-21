local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

T["find_blocks_async exposes existing and generated block candidates"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["target.md"] = "Alpha block ^existing\n\nBeta unlabeled",
  })

  local result = h.child_await(
    child,
    [[
      require("obsidian.search").find_blocks_async("alpha", function(matches)
        done(vim.tbl_map(function(match)
          return {
            text = match.text,
            id = match.block.id,
            existing = match.existing,
          }
        end, matches))
      end)
    ]],
    { desc = "block search" }
  )

  eq({ { text = "Alpha block", id = "^existing", existing = true } }, result)
end

T["find_blocks_async lazily reuses the vault index"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["target.md"] = "Alpha block\n\nBeta block",
  })

  local result = h.child_await(
    child,
    [[
      local search = require "obsidian.search"
      local original = search.find_notes_async
      local scans = 0
      search.find_notes_async = function(...)
        scans = scans + 1
        return original(...)
      end
      search.find_blocks_async("alpha", function(alpha)
        search.find_blocks_async("beta", function(beta)
          search.find_notes_async = original
          done({ scans = scans, alpha = #alpha, beta = #beta, generated = beta[1] and not beta[1].existing })
        end)
      end)
    ]],
    { desc = "reused block index" }
  )

  eq({ scans = 1, alpha = 1, beta = 1, generated = true }, result)
end

return T
