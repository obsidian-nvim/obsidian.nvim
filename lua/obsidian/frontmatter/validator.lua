---@type table<string, fun(v: any, path: string): any, string?>
local validator = {}

validator.id = function(v, path)
  if type(v) == "string" or type(v) == "number" then
    return tostring(v)
  else
    return nil,
      string.format(
        "Invalid id '%s' in frontmatter for %s, Expected string or number found %s",
        vim.inspect(v),
        tostring(path),
        type(v)
      )
  end
end

validator.aliases = function(v, path)
  local aliases = {}
  if type(v) == "table" then
    for _, alias in ipairs(v) do
      if type(alias) == "string" then
        table.insert(aliases, alias)
      else
        return nil,
          string.format(
            "Invalid alias '%s' in frontmatter for %s. Expected string, found %s",
            vim.inspect(alias),
            tostring(path),
            type(alias)
          )
      end
    end
  elseif type(v) == "string" then
    table.insert(aliases, v)
  else
    return nil, string.format("Invalid aliases '%s' in frontmatter for %s", vim.inspect(v), tostring(path))
  end

  return aliases
end

validator.tags = function(v, path)
  local tags = {}
  if type(v) == "table" then
    for _, tag in ipairs(v) do
      if type(tag) == "string" then
        table.insert(tags, tag)
      else
        return nil,
          string.format(
            "Invalid tag '%s' found in frontmatter for %s. Expected string, found %s",
            vim.inspect(tag),
            tostring(path),
            type(tag)
          )
      end
    end
  elseif type(v) == "string" then
    table.insert(tags, v)
  else
    return nil, string.format("Invalid tags in frontmatter for '%s'", path)
  end

  return tags
end

return validator
