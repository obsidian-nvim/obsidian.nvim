---@param data obsidian.CommandArgs
return function(data)
  local subcmd = data.args:len() > 0 and data.args or nil
  -- TODO: doc on how this command behaves
  -- TODO: if sync.enabled and no conigured vault -> run wizard
  require("obsidian.sync").menu(subcmd)
end
