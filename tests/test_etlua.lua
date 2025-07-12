local M = require "obsidian.lib.etlua"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local has_error = MiniTest.expect.error

local T = new_set()

T["Parser"] = new_set()

local cases = {
  {
    "hello world",
    "hello world",
  },

  {
    "one surf-zone two",
    "one <%= var %> two",
    { var = "surf-zone" },
  },

  {
    "a ((1))((2))((3)) b",
    "a <% for i=1,3 do %>((<%= i %>))<% end %> b",
  },

  {
    "y%&gt;u",
    [[<%= "y%>u" %>]],
  },

  {
    "y%>u",
    [[<%- "y%>u" %>]],
  },

  {
    [[
This is my message to you
This is my message to 4



  hello 1
  hello 2
  hello 3
  hello 4
  hello 5
  hello 6
  hello 7
  hello 8
  hello 9
  hello 10

message: yeah

This is my message to oh yeah  %&gt;&quot;]],
    [[
This is my message to <%= "you" %>
This is my message to <%= 4 %>
<% if things then %>
  I love things
<% end %>

<% for i=1,10 do%>
  hello <%= i -%>
<% end %>

message: <%= visitor %>

This is my message to <%= [=[oh yeah  %>"]=] %>]],
    {
      visitor = "yeah",
    },
  },

  {
    "hello",
    "<%= 'hello' -%>",
  },

  -- should have access to _G
  {
    "",
    "<% assert(true) %>",
    { hello = "world" },
  },
}

T["Parser"]["render"] = new_set {
  parametrize = cases,
}

T["Parser"]["render"]["works"] = function(expect, ...)
  eq(expect, M.render(...))
end

T["Parser"]["error on unclosed tag"] = function()
  has_error(function()
    assert(M.render "hello <%=world")
  end)
end

T["Parser"]["should fail on bad interpolate tag"] = function()
  has_error(function()
    assert(M.render "hello <%= if hello then print(nil) end%>")
  end)
end

T["Parser"]["should fail on bad tag"] = function()
  has_error(function()
    assert(M.render [[
          what is going on
          hello <% howdy doody %>
          there is nothing left
        ]])
  end)
end

T["Parser"]["should use existing buffer"] = function()
  local fn = M.compile "hello<%= 'yeah' %>"
  local buff = { "first" }
  local out = fn({}, buff, #buff)
  eq("firsthelloyeah", out)
end

T["Parser"]["should compile readme example"] = function()
  local parser = M.Parser()

  local first_fn = parser:load(parser:compile_to_lua "Hello ")
  local second_fn = parser:load(parser:compile_to_lua "World")

  local buffer = {}
  parser:run(first_fn, nil, buffer, #buffer)
  parser:run(second_fn, nil, buffer, #buffer)

  eq("Hello World", table.concat(buffer))
end

T["Parser"]["in_string"] = function()
  local params = {
    { "hello world", false },
    { "hello 'world", true },
    { [[hello "hello \" world]], true },
    { "hello [=[ wor'ld ]=]dad", false },
  }

  for _, case in ipairs(params) do
    local str, expected = unpack(case)
    eq(expected, M.Parser.in_string({ str = str }, 1))
  end
end

return T
