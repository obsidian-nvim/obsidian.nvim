return function(data)
  local query = vim.trim(data.args or "")
  require("obsidian.interfaces.help").pick(query)
end
