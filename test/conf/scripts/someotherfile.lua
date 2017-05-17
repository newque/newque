local module = {}

function module.add_stuff(strings)
  table.insert(strings, "added by an external script")
  return strings
end

return module
