--- JSON formatter. Thin wrapper around vim.json.encode. The entire
--- VaultStats object is encoded as-is, so every field documented in
--- `obsidian.stats.VaultStats` is available to downstream tooling.

local M = {}

---@param stats obsidian.stats.VaultStats
---@param opts  { pretty: boolean|? }
---@return string
function M.render(stats, opts)
  local encoded = vim.json.encode(stats)
  if opts.pretty then
    -- Cheap pretty-print via jq-less reindentation on 1-level commas. Kept
    -- optional; most consumers will run this through jq themselves.
    return vim.fn.system({ "jq", "." }, encoded)
  end
  return encoded
end

return M
