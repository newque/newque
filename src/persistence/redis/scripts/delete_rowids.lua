local delete_rowids = function (rowids, index_id_key, index_ts_key, data_key, meta_key, debug)

  redis.call('zremrangebyscore', data_key, rowids[1], rowids[#rowids])

  for i = 1, #rowids do
    local rowid = rowids[i]

    local lookup = redis.call('hmget', meta_key, 'id:'..rowid, 'ts:'..rowid)

    redis.call('hdel', meta_key, 'rowid:'..lookup[1], 'id:'..rowid, 'ts:'..rowid)
    redis.call('zrem', index_id_key, lookup[1]..':'..rowid)
    redis.call('zrem', index_ts_key, lookup[2]..':'..rowid)

  end
end
