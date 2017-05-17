local m = require("someotherfile")

return function (ids, messages)
  messages[1] = string.upper(messages[1])

  error({location="throws.lua, main mapper", message="blew up!"})

  return ids, messages
end
