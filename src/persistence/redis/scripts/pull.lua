-- https://redis.io/topics/indexes

local index_id_key = KEYS[1]
local index_ts_key = KEYS[2]
local data_key = KEYS[3]
local meta_key = KEYS[4]
local limit = tonumber(ARGV[1])
local filter_type = ARGV[2]
local filter_value = ARGV[3]
local only_once = ARGV[4] == "true"
local fetch_last = ARGV[5] == "true"

local start_rowid
local start_mode
local debug = {
  'limit:', limit,
  'filter_type:', filter_type,
  'filter_value:', filter_value,
  'only_once:', tostring(only_once),
  'fetch_last', tostring(fetch_last)
}

if filter_type == 'after_id' then
  local index_lookup = redis.call(
    'zrangebylex', index_id_key,
    '['..filter_value..':', '+',
    'limit', 0, 1
  )

  table.insert(debug, 'index_lookup:'..tostring(index_lookup))

  if #index_lookup == 0 then
    start_rowid = nil
  else
    local id_retrieved = string.sub(index_lookup[1], 1, string.find(index_lookup[1], ':') - 1)

    table.insert(debug, 'id_retrieved:'..tostring(id_retrieved))

    if id_retrieved ~= filter_value then
      start_rowid = nil
    else
      start_rowid = string.sub(index_lookup[1], #id_retrieved + 2)
      start_mode = '('
    end
  end

elseif filter_type == 'after_ts' then
  filter_value = string.rep('0', 19 - #filter_value)..filter_value -- left pad
  local index_lookup = redis.call(
    'zrangebylex', index_ts_key,
    '('..filter_value..':999999999999', '+',
    'limit', 0, 1
  )

  table.insert(debug, 'index_lookup:'..tostring(index_lookup))

  if #index_lookup == 0 then
    start_rowid = nil
  else
    start_rowid = string.sub(index_lookup[1], string.find(index_lookup[1], ':') + 1)
    start_mode = ''
  end

elseif filter_type == 'after_rowid' then
  start_rowid = tonumber(filter_value)
  start_mode = '('
else
  return redis.error_reply('Invalid filter_type argument: ['..filter_type..']')
end

if start_rowid == nil then
  table.insert(debug, 'EXIT 1')
  return {{}, '', '', '', debug}
end

table.insert(debug, 'start_rowid:'..tostring(start_rowid))
table.insert(debug, 'start_mode:'..tostring(start_mode))

local main_lookup_args = {
  'zrangebyscore', data_key,
  (start_mode..tostring(start_rowid)), '+inf',
  'limit', 0, limit
}

for i = 1, #main_lookup_args do
  table.insert(debug, main_lookup_args[i])
end

local msgs_rowid = redis.call(unpack(main_lookup_args))

if #msgs_rowid == 0 then
  table.insert(debug, 'EXIT 2')
  return {{}, '', '', '', debug}
end

local msgs = {}
local rowids = {}

for i = 1, #msgs_rowid do
  local pos = string.find(msgs_rowid[i], ':')
  table.insert(msgs, string.sub(msgs_rowid[i], pos + 1))
  table.insert(rowids, string.sub(msgs_rowid[i], 1, pos - 1))
end

local last_rowid = rowids[#rowids]

local last_msg_meta
if fetch_last then
  last_msg_meta = redis.call(
    'hmget', meta_key,
    'id:'..last_rowid,
    'ts:'..last_rowid
  )
end

local last_id
local last_timens
if last_msg_meta ~= nil and #last_msg_meta == 2 then
  last_id = last_msg_meta[1]
  last_timens = last_msg_meta[2]
else
  last_id = ''
  last_timens = ''
end

table.insert(debug, 'last_id:'..tostring(last_id))
table.insert(debug, 'last_timens:'..tostring(last_timens))

if only_once then
  delete_rowids(rowids, index_id_key, index_ts_key, data_key, meta_key, debug)
end

return {msgs, last_rowid, last_id, last_timens, debug}
