local index_id_key = KEYS[1]
local index_ts_key = KEYS[2]
local data_key = KEYS[3]
local meta_key = KEYS[4]

-- Check that the cardinality of all of this channel's data structures match.

local data_size = redis.call('zcard', data_key)
local index_id_size = redis.call('zcard', index_id_key)
local index_ts_size = redis.call('zcard', index_ts_key)
local meta_size = redis.call('hlen', meta_key)

if (meta_size == 0 and data_size == 0 and index_id_size == 0 and index_ts_size == 0)
    or (index_id_size == data_size and index_ts_size == data_size and meta_size == (data_size * 3 + 1))
    then
  return 'OK'
else
  return {data_size, index_id_size, index_ts_size, meta_size}
end
