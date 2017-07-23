-- https://redis.io/topics/indexes

local index_id_key = KEYS[1]
local index_ts_key = KEYS[2]
local data_key = KEYS[3]
local meta_key = KEYS[4]

local size = redis.call('zcard', data_key)

return size
