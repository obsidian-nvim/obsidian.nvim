local obsidian = require "obsidian"
local client = obsidian.setup { dir = "/home/frainx8/Documents/TestVault" }

local cache = require("obsidian.cache").new(client)

cache:index_vault(client)
