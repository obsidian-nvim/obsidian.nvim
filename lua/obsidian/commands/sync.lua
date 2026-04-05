return function()
  -- TODO: if sync.enabled and no conigured vault -> run wizard
  -- TODO: accept argument and auto complete
  require("obsidian.sync").menu()
end
