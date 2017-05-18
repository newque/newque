local m = require("someotherfile")

return function (ids, messages)
  new_ids = {}
  new_msgs = {}

  for i = 1, #messages do
    if string.find(messages[i], "2") then
      table.insert(new_ids, ids[i])
      table.insert(new_msgs, messages[i])
    end
  end

  return m.add_stuff(new_ids), m.add_stuff(new_msgs)
end
