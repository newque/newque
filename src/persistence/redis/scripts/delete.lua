local index_id_key = KEYS[1]
local index_ts_key = KEYS[2]
local data_key = KEYS[3]
local meta_key = KEYS[4]

redis.call('del', index_id_key, index_ts_key, data_key, meta_key)

return 'OK'
