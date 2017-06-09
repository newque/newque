-- https://redis.io/topics/indexes

local index_id_key = KEYS[1]
local index_ts_key = KEYS[2]
local data_key = KEYS[3]
local meta_key = KEYS[4]
local limit = ARGV[1]
local filter_type = ARGV[2]
local filter_value = ARGV[3]
local only_once = ARGV[4]
local fetch_last = ARGV[5]

local start_rowid
local output

local pattern = '(.*):'

if filter_type == 'after_id' then
  local index_lookup = redis.call(
    'zrangebylex', index_id_key,
    '['..filter_value, '+',
    'limit', 0, 2
  )

  local id_retrieved = string.match(index_lookup[1], pattern)
  if id_retrieved ~= filter_value then
    return {}
  end
  start_rowid = string.sub(index_lookup[2], #(string.match(index_lookup[2], pattern)) + 2)

  output = {'AFTER_ID', start_rowid}

elseif filter_type == 'after_ts' then
  filter_value = string.rep('0', 19 - #filter_value)..filter_value -- left pad
  local index_lookup = redis.call(
    'zrangebylex', index_ts_key,
    '('..filter_value..':999999999999', '+',
    'limit', 0, 1
  )

  if #index_lookup == 0 then
    return {}
  end

  local id_retrieved = string.match(index_lookup[1], pattern)
  start_rowid = string.sub(index_lookup[1], #id_retrieved + 2)

  output = {'AFTER_TS', id_retrieved, start_rowid}

elseif filter_type == 'after_rowid' then
  start_rowid = tonumber(filter_value) + 1

else
  return redis.error_reply('Invalid filter_type argument: ['..filter_type..']')
end

local msgs_rowid = redis.call(
  'zrangebyscore', data_key,
  start_rowid, '+inf', 'WITHSCORES',
  'limit', 0, limit
)

local last_rowid = msgs_rowid[#msgs_rowid]
local msgs = {}
for i = 1, #msgs_rowid, 2 do
  table.insert(msgs, msgs_rowid[i])
end

local last_msg_meta = redis.call(
  'hmget', meta_key,
  'id:'..last_rowid,
  'ts:'..last_rowid
)

-- TODO: fetch_last
-- TODO: only_once, using ZREMRANGEBYSCORE

return {msgs, last_rowid, last_msg_meta[1], last_msg_meta[2]}
