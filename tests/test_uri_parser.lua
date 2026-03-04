local uri = require "obsidian.uri"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

---------------------
--- parse: basics ---
---------------------

T["parse"] = new_set()

T["parse"]["returns nil for non-obsidian URIs"] = function()
  eq(nil, uri.parse "https://example.com")
  eq(nil, uri.parse "file:///foo/bar")
  eq(nil, uri.parse "not-a-uri")
end

---------------------------------------------
--- parse: standard form (action + params) ---
---------------------------------------------

T["parse_open"] = new_set()

T["parse_open"]["open vault only"] = function()
  local p = uri.parse "obsidian://open?vault=my%20vault"
  eq("open", p.action)
  eq("my vault", p.vault)
  eq(nil, p.file)
  eq(nil, p.path)
end

T["parse_open"]["open vault by ID"] = function()
  local p = uri.parse "obsidian://open?vault=ef6ca3e3b524d22f"
  eq("open", p.action)
  eq("ef6ca3e3b524d22f", p.vault)
end

T["parse_open"]["open vault + file"] = function()
  local p = uri.parse "obsidian://open?vault=my%20vault&file=my%20note"
  eq("open", p.action)
  eq("my vault", p.vault)
  eq("my note", p.file)
end

T["parse_open"]["open with absolute path"] = function()
  local p = uri.parse "obsidian://open?path=%2Fhome%2Fuser%2Fmy%20vault%2Fpath%2Fto%2Fmy%20note"
  eq("open", p.action)
  eq("/home/user/my vault/path/to/my note", p.path)
end

T["parse_open"]["open with heading anchor"] = function()
  local p = uri.parse "obsidian://open?vault=vault&file=Note%23Heading"
  eq("open", p.action)
  eq("Note", p.file)
  eq("#Heading", p.anchor)
end

T["parse_open"]["open with block reference"] = function()
  local p = uri.parse "obsidian://open?vault=vault&file=Note%23%5EBlock"
  eq("open", p.action)
  eq("Note", p.file)
  eq("#^Block", p.anchor)
end

T["parse_open"]["strips .md extension from file"] = function()
  local p = uri.parse "obsidian://open?vault=vault&file=my%20note.md"
  eq("my note", p.file)
end

T["parse_open"]["preserves file with path components"] = function()
  local p = uri.parse "obsidian://open?vault=vault&file=path%2Fto%2Fnote"
  eq("path/to/note", p.file)
end

T["parse_open"]["paneType is parsed"] = function()
  local p = uri.parse "obsidian://open?vault=vault&file=note&paneType=tab"
  eq("tab", p.pane_type)
end

---------------------------------
--- parse: shorthand forms ------
---------------------------------

T["parse_shorthand"] = new_set()

T["parse_shorthand"]["vault/file shorthand"] = function()
  local p = uri.parse "obsidian://my%20vault/my%20note"
  eq("open", p.action)
  eq("my vault", p.vault)
  eq("my note", p.file)
end

T["parse_shorthand"]["vault/path/to/file shorthand"] = function()
  local p = uri.parse "obsidian://my%20vault/path/to/my%20note"
  eq("open", p.action)
  eq("my vault", p.vault)
  eq("path/to/my note", p.file)
end

T["parse_shorthand"]["vault only shorthand"] = function()
  local p = uri.parse "obsidian://my%20vault"
  eq("open", p.action)
  eq("my vault", p.vault)
  eq(nil, p.file)
end

T["parse_shorthand"]["absolute path shorthand (triple slash)"] = function()
  local p = uri.parse "obsidian:///home/user/vault/note"
  eq("open", p.action)
  eq("/home/user/vault/note", p.path)
  eq(nil, p.vault)
end

----------------------------
--- parse: new action ------
----------------------------

T["parse_new"] = new_set()

T["parse_new"]["new with name"] = function()
  local p = uri.parse "obsidian://new?vault=my%20vault&name=my%20note"
  eq("new", p.action)
  eq("my vault", p.vault)
  eq("my note", p.name)
end

T["parse_new"]["new with file path"] = function()
  local p = uri.parse "obsidian://new?vault=my%20vault&file=path%2Fto%2Fmy%20note"
  eq("new", p.action)
  eq("path/to/my note", p.file)
end

T["parse_new"]["new with content"] = function()
  local p = uri.parse "obsidian://new?vault=vault&name=note&content=Hello%20World"
  eq("new", p.action)
  eq("Hello World", p.content)
  eq(false, p.clipboard)
end

T["parse_new"]["new with clipboard flag"] = function()
  local p = uri.parse "obsidian://new?vault=vault&name=note&clipboard"
  eq(true, p.clipboard)
end

T["parse_new"]["new with silent flag"] = function()
  local p = uri.parse "obsidian://new?vault=vault&name=note&silent"
  eq(true, p.silent)
end

T["parse_new"]["new with append flag"] = function()
  local p = uri.parse "obsidian://new?vault=vault&name=note&append"
  eq(true, p.append)
end

T["parse_new"]["new with overwrite flag"] = function()
  local p = uri.parse "obsidian://new?vault=vault&name=note&overwrite"
  eq(true, p.overwrite)
end

T["parse_new"]["new with prepend flag"] = function()
  local p = uri.parse "obsidian://new?vault=vault&name=note&prepend"
  eq(true, p.prepend)
end

T["parse_new"]["new with x-success callback"] = function()
  local p = uri.parse "obsidian://new?vault=vault&name=note&x-success=myapp%3A%2F%2Fx-callback-url"
  eq("myapp://x-callback-url", p.x_success)
end

------------------------------
--- parse: daily action ------
------------------------------

T["parse_daily"] = new_set()

T["parse_daily"]["daily with vault"] = function()
  local p = uri.parse "obsidian://daily?vault=my%20vault"
  eq("daily", p.action)
  eq("my vault", p.vault)
end

T["parse_daily"]["daily with no params"] = function()
  local p = uri.parse "obsidian://daily"
  eq("daily", p.action)
  eq(nil, p.vault)
end

-------------------------------
--- parse: unique action ------
-------------------------------

T["parse_unique"] = new_set()

T["parse_unique"]["unique with vault"] = function()
  local p = uri.parse "obsidian://unique?vault=my%20vault"
  eq("unique", p.action)
  eq("my vault", p.vault)
end

T["parse_unique"]["unique with content"] = function()
  local p = uri.parse "obsidian://unique?vault=vault&content=Hello%20World"
  eq("unique", p.action)
  eq("Hello World", p.content)
end

-------------------------------
--- parse: search action ------
-------------------------------

T["parse_search"] = new_set()

T["parse_search"]["search with query"] = function()
  local p = uri.parse "obsidian://search?vault=my%20vault&query=Obsidian"
  eq("search", p.action)
  eq("Obsidian", p.query)
end

T["parse_search"]["search with no query"] = function()
  local p = uri.parse "obsidian://search?vault=my%20vault"
  eq("search", p.action)
  eq(nil, p.query)
end

--------------------------------------
--- parse: choose-vault action ------
--------------------------------------

T["parse_choose_vault"] = new_set()

T["parse_choose_vault"]["choose-vault"] = function()
  local p = uri.parse "obsidian://choose-vault"
  eq("choose-vault", p.action)
end

-------------------------------------------
--- parse: hook-get-address action ------
-------------------------------------------

T["parse_hook"] = new_set()

T["parse_hook"]["hook-get-address"] = function()
  local p = uri.parse "obsidian://hook-get-address?vault=vault"
  eq("hook-get-address", p.action)
  eq("vault", p.vault)
end

T["parse_hook"]["hook-get-address with x-success"] = function()
  local p = uri.parse "obsidian://hook-get-address?vault=vault&x-success=hook%3A%2F%2Fcallback"
  eq("hook-get-address", p.action)
  eq("hook://callback", p.x_success)
end

-----------------------------------------
--- parse: encoding edge cases ----------
-----------------------------------------

T["parse_encoding"] = new_set()

T["parse_encoding"]["plus signs in query values decoded as spaces"] = function()
  local p = uri.parse "obsidian://new?vault=vault&content=hello+world"
  eq("hello world", p.content)
end

T["parse_encoding"]["multiple percent-encoded special chars"] = function()
  local p = uri.parse "obsidian://open?vault=my%20vault&file=folder%2Fmy%20note%20(draft)"
  eq("my vault", p.vault)
  eq("folder/my note (draft)", p.file)
end

T["parse_encoding"]["anchor with encoded hash and caret"] = function()
  -- obsidian://open?vault=vault&file=Note%23%5Eblock-id
  -- %23 = #, %5E = ^
  local p = uri.parse "obsidian://open?vault=vault&file=Note%23%5Eblock-id"
  eq("Note", p.file)
  eq("#^block-id", p.anchor)
end

T["parse_encoding"]["anchor from path parameter"] = function()
  local p = uri.parse "obsidian://open?path=%2Fhome%2Fuser%2Fvault%2FNote%23Heading"
  eq("/home/user/vault/Note", p.path)
  eq("#Heading", p.anchor)
end

--------------------------------------
--- parse: boolean param handling ----
--------------------------------------

T["parse_booleans"] = new_set()

T["parse_booleans"]["bare params without values are boolean true"] = function()
  local p = uri.parse "obsidian://new?vault=vault&name=note&silent&clipboard&append"
  eq(true, p.silent)
  eq(true, p.clipboard)
  eq(true, p.append)
end

T["parse_booleans"]["absent params are boolean false"] = function()
  local p = uri.parse "obsidian://new?vault=vault&name=note"
  eq(false, p.silent)
  eq(false, p.clipboard)
  eq(false, p.append)
  eq(false, p.prepend)
  eq(false, p.overwrite)
end

return T
