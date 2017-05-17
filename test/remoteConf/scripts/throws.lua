local m = require("someotherfile")

return function (ids, messages)

  error({location="my script", message="BOOM!"})

  return ids, messages
end
