local M = {}
local INPUT_CANCELLED = "~~~INPUT-CANCELLED~~~"

--- Prompt synchronously. Returns nil on cancellation, or trimmed text (possibly empty).
---@param prompt string
---@param opts { completion: string?, default: string? }?
---@return string?
function M.input(prompt, opts)
  opts = opts or {}
  if not vim.endswith(prompt, ": ") then
    prompt = prompt .. ": "
  end

  local input = vim.trim(
    vim.fn.input { prompt = prompt, completion = opts.completion, default = opts.default, cancelreturn = INPUT_CANCELLED }
  )
  if input == INPUT_CANCELLED then
    return nil
  end
  return input
end

--- Prompt synchronously and return the selected label without mnemonic markers.
---@param prompt string
---@param choices string? Newline-separated labels with optional '&' mnemonics.
---@return string?
function M.confirm(prompt, choices)
  choices = choices or "&Yes\n&No"
  local labels = vim.split(choices, "\n")
  local choice = labels[vim.fn.confirm(prompt, choices)]
  if not choice then
    return nil
  end
  return (choice:gsub("&", ""))
end

return M
