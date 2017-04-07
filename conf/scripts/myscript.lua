local m = require("someotherfile")

function sleep(n)
  os.execute("sleep " .. tonumber(n))
end


return function (ids, messages)
  table.insert(ids, "id-myscript-1")
  table.insert(ids, "id-myscript-2")

  table.insert(messages, "msg-myscript-1")
  table.insert(messages, "msg-myscript-2")

  -- Proof that blocking scripts don't block Newque
  sleep(2)

  return m.add_stuff(ids), m.add_stuff(messages)
end
