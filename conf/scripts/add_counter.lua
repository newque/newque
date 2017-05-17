-- This script sleeps for 2 seconds, then prepends the value of a counter to every message

function sleep(n)
  os.execute("sleep " .. tonumber(n))
end


message_counter = 1

return function (ids, messages)

  -- Proof that blocking scripts don't block Newque
  sleep(2)

  for i = 1, #messages do
    messages[i] = message_counter .. " " .. messages[i]
    message_counter = message_counter + 1
  end

  return ids, messages
end
