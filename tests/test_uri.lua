local M = require "obsidian.util"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["is_uri"] = new_set {
  parametrize = {
    -- Web
    { "https", "https://example.com" },
    { "http", "http://localhost:8080" },
    { "https", "https://example.com/path?x=1&y=two#section" },
    { "https", "https://[2001:db8::1]/index.html" },

    -- Mail
    { "mailto", "mailto:mail@domain.com" },
    { "mailto", "mailto:mail@domain.com?subject=Hello&body=Hi%20there" },

    -- Files
    { "file", "file:///home/user/vault/note.md" },
    { "file", "file:///C:/Users/Neo/Documents/Obsidian%20Vault/note.md" },

    -- Phone / messages
    { "tel", "tel:+447700900123" },
    { "sms", "sms:+447700900123" },

    -- Maps / geo
    { "geo", "geo:51.5074,-0.1278" },
    { "geo", "geo:0,0?q=King%27s%20College%20London" },

    -- Calendar subscription
    { "webcal", "webcal://example.com/calendar.ics" },

    -- Obsidian deep links
    { "obsidian", "obsidian://open?vault=Vault&file=Inbox%2FNote" },
    { "obsidian", "obsidian://open?path=/home/user/Vault/Inbox/Note.md" },

    -- Research / study tooling
    { "zotero", "zotero://select/library/items/ABCDEFGH" },
    { "zotero", "zotero://open-pdf/library/items/ABCDEFGH?page=3" },
    { "anki", "anki://x-callback-url/addnote?deck=Default&note=Basic" },

    -- Editor / dev tooling
    { "vscode", "vscode://file/home/user/vault/note.md:10:2" },

    -- Chat / community (often in project notes)
    { "slack", "slack://channel?team=T123&id=C456" },
    { "discord", "discord://discord.com/channels/123/456" },
    { "tg", "tg://resolve?domain=some_channel" },

    -- Media (common in music notes)
    { "spotify", "spotify:track:6rqhFgbbKwnb9MLmUQDhG6" },
    { "spotify", "spotify://track/6rqhFgbbKwnb9MLmUQDhG6" },
  },
}

T["is_uri"]["identify different uri schemes"] = function(expected_scheme, uri)
  local is_uri, scheme = M.is_uri(uri)
  eq(true, is_uri)
  eq(expected_scheme, scheme)
end

T["is_uri_negative"] = new_set {
  parametrize = {
    -- Common “looks like scheme” false positives / non-URIs in Obsidian
    { "C:\\Users\\Neo\\Vault\\note.md" }, -- Windows path (drive letter)
    { "/home/user/vault/note.md" }, -- plain path
    { "some note: with colon" }, -- colon in plain text
  },
}

T["is_uri_negative"]["do not treat non-uris as uri"] = function(s)
  local is_uri = M.is_uri(s)
  eq(false, is_uri)
end

return T
