return function(_, params, handler, _)
  params.documentation = {
    value = [[# Heading 1
[link](https://example.com)
     ]],
    kind = "markdown",
  }
  handler(nil, params)
end
