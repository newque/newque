-- https://redis.io/topics/indexes

local index_id_key = KEYS[1]
local index_ts_key = KEYS[2]
local data_key = KEYS[3]
local meta_key = KEYS[4]
local ts = string.rep('0', 19 - #ARGV[1])..ARGV[1] -- left pad

local next_rowid = redis.call('hget', meta_key, 'next_rowid')
if next_rowid == false then
  next_rowid = 0
end

for i = 2, #ARGV, 2 do
  local rowid = next_rowid
  next_rowid = next_rowid + 1

  -- Store the non-indexed "columns"
  redis.call('hmset', meta_key, 'id:'..rowid, ARGV[i], 'ts:'..rowid, ts)

  -- Store the message itself, with the rowid as Score
  redis.call('zadd', data_key, rowid, ARGV[i + 1])

  -- Index the message by id, lexicographically
  redis.call('zadd', index_id_key, 0, ARGV[i]..':'..rowid)

  -- Index the message by ts, lexicographically
  redis.call('zadd', index_ts_key, 0, ts..':'..rowid)

end

redis.call('hset', meta_key, 'next_rowid', next_rowid)

return redis.status_reply('OK')
