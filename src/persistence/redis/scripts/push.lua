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

local messages_length = (#ARGV - 1) / 2
local saved = 0

for i = 2, (messages_length + 1) do
  local msg = ARGV[i]
  local id = ARGV[i + messages_length]
  local rowid = next_rowid

  local id_exists = redis.call('hsetnx', meta_key, 'rowid:'..id, rowid)

  if id_exists == 1 then

    -- Store the non-indexed "columns"
    redis.call('hmset', meta_key, 'id:'..rowid, id, 'ts:'..rowid, ts)

    -- Store the message itself, with the rowid as Score
    -- Prepend the rowid to avoid collisions
    redis.call('zadd', data_key, rowid, rowid..':'..msg)

    -- Index the message by id, lexicographically
    redis.call('zadd', index_id_key, 0, id..':'..rowid)

    -- Index the message by ts, lexicographically
    redis.call('zadd', index_ts_key, 0, ts..':'..rowid)

    saved = saved + 1

    -- Increment next_rowid for next usage
    next_rowid = next_rowid + 1

  end
end

redis.call('hset', meta_key, 'next_rowid', next_rowid)

return saved
