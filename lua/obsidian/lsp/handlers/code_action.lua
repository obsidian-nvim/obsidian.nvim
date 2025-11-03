---@param params lsp.CodeActionParams
return function(params, handler)
  handler(nil, {
    {
      title = "add_file_property",
      command = {
        title = "add_file_property",
        command = "add_file_property",
        -- arguments
      },
    },
  })
end
