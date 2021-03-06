'use strict'

global.Promise = require('bluebird')
global.Fn = require('./fn')
global.Scenarios = require('./scenarios')
global.C = require('./constants')
global.Proc = require('./proc')

var localSettings = {
}

var httpJsonSettings = {
  baseUrls: ['http://127.0.0.1:' + C.remotePort + '/v1/'],
  baseHeaders: [{key: 'secret-token', value: 'supersecret'}],
  timeout: 1000,
  appendChannelName: true
}
var httpPlaintextSettings = {
  baseUrls: ['http://127.0.0.1:' + C.remotePort + '/v1/'],
  baseHeaders: [{key: 'secret-token', value: 'supersecret'}],
  timeout: 1000,
  appendChannelName: true,
  remoteInputFormat: 'plaintext',
  remoteOutputFormat: 'plaintext'
}
var esSettings = {
  baseUrls: ['http://127.0.0.1:9200'],
  // index is configured in the setup
  type: 'test-type',
  timeout: C.esTimeout
}
var pubsubSettings = {
  host: '0.0.0.0',
  port: 8500
}
var fifoSettings = {
  host: '0.0.0.0',
  port: 8500,
  timeout: 1000,
  healthTimeLimit: 1000
}

var redisSettings = {
  host: '127.0.0.1',
  port: 6379
}

var redisPubsubSettings = {
  host: '127.0.0.1',
  port: 6379,
  broadcast: "somechannel"
}

Proc.pathExists(Proc.newquePath)
.then(function (exists) {
  if (!exists) {
    throw new Error('Newque executable not found at ' + Proc.newquePath)
  }
})
.then(Proc.clearEs(esSettings))
.then(Proc.clearRedis(redisSettings))
.then(function (server) {

  require('./sections/admin')('none', {}, false)

  require('./sections/count')('disk', localSettings, false)
  require('./sections/count')('disk', localSettings, true)
  require('./sections/count')('memory', localSettings, false)
  require('./sections/count')('memory', localSettings, true)
  require('./sections/count')('httpproxy json', httpJsonSettings, false)
  require('./sections/count')('httpproxy plaintext', httpPlaintextSettings, false)
  require('./sections/count')('httpproxy json', httpJsonSettings, true)
  require('./sections/count')('httpproxy plaintext', httpPlaintextSettings, true)
  require('./sections/count')('fifo', fifoSettings, false)
  require('./sections/count')('fifo', fifoSettings, true)
  require('./sections/count')('elasticsearch', esSettings, true)
  require('./sections/count')('redis', redisSettings, false)
  require('./sections/count')('redis', redisSettings, true)

  require('./sections/push')('disk', localSettings, false)
  require('./sections/push')('disk', localSettings, true)
  require('./sections/push')('memory', localSettings, false)
  require('./sections/push')('memory', localSettings, true)
  require('./sections/push')('httpproxy json', httpJsonSettings, false)
  require('./sections/push')('httpproxy plaintext', httpPlaintextSettings, false)
  require('./sections/push')('httpproxy json', httpJsonSettings, true)
  require('./sections/push')('httpproxy plaintext', httpPlaintextSettings, true)
  require('./sections/push')('fifo', fifoSettings, false)
  require('./sections/push')('fifo', fifoSettings, true)
  require('./sections/push')('elasticsearch', esSettings, true)
  require('./sections/push')('redis', redisSettings, false)
  require('./sections/push')('redis', redisSettings, true)

  require('./sections/pull')('disk', localSettings, false)
  require('./sections/pull')('disk', localSettings, true)
  require('./sections/pull')('memory', localSettings, false)
  require('./sections/pull')('memory', localSettings, true)
  require('./sections/pull')('httpproxy json', httpJsonSettings, false)
  require('./sections/pull')('httpproxy plaintext', httpPlaintextSettings, false)
  require('./sections/pull')('httpproxy json', httpJsonSettings, true)
  require('./sections/pull')('httpproxy plaintext', httpPlaintextSettings, true)
  require('./sections/pull')('fifo', fifoSettings, true)
  require('./sections/pull')('redis', redisSettings, false)
  require('./sections/pull')('redis', redisSettings, true)

  require('./sections/ack')('disk', localSettings, false)
  require('./sections/ack')('disk', localSettings, true)
  require('./sections/ack')('memory', localSettings, false)
  require('./sections/ack')('memory', localSettings, true)
  require('./sections/ack')('httpproxy json', httpJsonSettings, false)
  require('./sections/ack')('httpproxy plaintext', httpPlaintextSettings, false)
  require('./sections/ack')('httpproxy json', httpJsonSettings, true)
  require('./sections/ack')('httpproxy plaintext', httpPlaintextSettings, true)
  require('./sections/ack')('fifo', fifoSettings, true)
  require('./sections/ack')('redis', redisSettings, false)
  require('./sections/ack')('redis', redisSettings, true)

  require('./sections/delete')('disk', localSettings, false)
  require('./sections/delete')('disk', localSettings, true)
  require('./sections/delete')('memory', localSettings, false)
  require('./sections/delete')('memory', localSettings, true)
  require('./sections/delete')('httpproxy json', httpJsonSettings, false)
  require('./sections/delete')('httpproxy plaintext', httpPlaintextSettings, false)
  require('./sections/delete')('httpproxy json', httpJsonSettings, true)
  require('./sections/delete')('httpproxy plaintext', httpPlaintextSettings, true)
  require('./sections/delete')('fifo', fifoSettings, false)
  require('./sections/delete')('fifo', fifoSettings, true)
  require('./sections/delete')('redis', redisSettings, false)
  require('./sections/delete')('redis', redisSettings, true)

  require('./sections/health')('none', {}, false)
  require('./sections/health')('disk', localSettings, false)
  require('./sections/health')('disk', localSettings, true)
  require('./sections/health')('memory', localSettings, false)
  require('./sections/health')('memory', localSettings, true)
  require('./sections/health')('httpproxy json', httpJsonSettings, false)
  require('./sections/health')('httpproxy plaintext', httpPlaintextSettings, false)
  require('./sections/health')('httpproxy json', httpJsonSettings, true)
  require('./sections/health')('httpproxy plaintext', httpPlaintextSettings, true)
  require('./sections/health')('pubsub', pubsubSettings, true)
  require('./sections/health')('fifo', fifoSettings, false)
  require('./sections/health')('fifo', fifoSettings, true)
  require('./sections/health')('elasticsearch', esSettings, true)
  require('./sections/health')('redis', redisSettings, false)
  require('./sections/health')('redis', redisSettings, true)

  require('./sections/large')('disk', localSettings, false)
  require('./sections/large')('disk', localSettings, true)
  require('./sections/large')('memory', localSettings, false)
  require('./sections/large')('memory', localSettings, true)
  require('./sections/large')('httpproxy json', httpJsonSettings, false)
  require('./sections/large')('httpproxy plaintext', httpPlaintextSettings, false)
  require('./sections/large')('httpproxy json', httpJsonSettings, true)
  require('./sections/large')('httpproxy plaintext', httpPlaintextSettings, true)
  require('./sections/large')('fifo', fifoSettings, false)
  require('./sections/large')('fifo', fifoSettings, true)
  require('./sections/large')('elasticsearch', esSettings, true)
  require('./sections/large')('redis', redisSettings, false)
  require('./sections/large')('redis', redisSettings, true)
  require('./sections/large')('pubsub', pubsubSettings, true)
  require('./sections/large')('redisPubsub', redisPubsubSettings, true)

  require('./sections/none')('none', {}, false)
  require('./sections/pubsub')('pubsub', pubsubSettings, true)
  require('./sections/redisPubsub')('redisPubsub', redisPubsubSettings, true)
  require('./sections/httpproxy')('httpproxy no-consumer', httpJsonSettings, true)
  require('./sections/fifo')('fifo no-consumer', fifoSettings, true)
  require('./sections/elasticsearch')('elasticsearch', esSettings, true)

  run()
})
