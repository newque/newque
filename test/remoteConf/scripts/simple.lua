return function (ids, messages)
  messages[1] = string.upper(messages[1])

  table.insert(ids, "added id 1")
  table.insert(ids, "added id 2")

  table.insert(messages, "added msg 1")
  table.insert(messages, "added msg 2")

  return ids, messages
end
