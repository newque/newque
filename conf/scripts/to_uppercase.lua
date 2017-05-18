-- This script upper cases every single message

return function (ids, messages)

  for i = 1, #messages do
    messages[i] = string.upper(messages[i])
  end

  return ids, messages
end
