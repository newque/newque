'use strict'

global.Promise = require('bluebird')
global.Fn = require('./fn')
global.Scenarios = require('./scenarios')
global.C = require('./constants')
global.Proc = require('./proc')

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
  timeout: 1000
}

Proc.pathExists(Proc.newquePath)
.then(function (exists) {
  if (!exists) {
    throw new Error('Newque executable not found at ' + Proc.newquePath)
  }
})
.then(Proc.clearEs(esSettings))
.then(function (server) {

  require('./sections/count')('disk', {}, false)
  require('./sections/count')('disk', {}, true)
  require('./sections/count')('memory', {}, false)
  require('./sections/count')('httpproxy json', httpJsonSettings, false)
  require('./sections/count')('httpproxy plaintext', httpPlaintextSettings, false)
  require('./sections/count')('fifo', fifoSettings, false)
  require('./sections/count')('fifo', fifoSettings, true)
  require('./sections/count')('elasticsearch', esSettings, true)

  require('./sections/push')('disk', {}, false)
  require('./sections/push')('disk', {}, true)
  require('./sections/push')('memory', {}, false)
  require('./sections/push')('httpproxy json', httpJsonSettings, false)
  require('./sections/push')('httpproxy plaintext', httpPlaintextSettings, false)
  require('./sections/push')('httpproxy json', httpJsonSettings, true)
  require('./sections/push')('httpproxy plaintext', httpPlaintextSettings, true)
  require('./sections/push')('fifo', fifoSettings, false)
  require('./sections/push')('fifo', fifoSettings, true)
  require('./sections/push')('elasticsearch', esSettings, true)

  require('./sections/pull')('disk', {}, false)
  require('./sections/pull')('disk', {}, true)
  require('./sections/pull')('memory', {}, false)
  require('./sections/pull')('httpproxy json', httpJsonSettings, false)
  require('./sections/pull')('httpproxy plaintext', httpPlaintextSettings, false)
  require('./sections/pull')('httpproxy json', httpJsonSettings, true)
  require('./sections/pull')('httpproxy plaintext', httpPlaintextSettings, true)
  require('./sections/pull')('fifo', fifoSettings, true)

  require('./sections/ack')('disk', {}, false)
  require('./sections/ack')('disk', {}, true)
  require('./sections/ack')('memory', {}, false)
  require('./sections/ack')('httpproxy json', httpJsonSettings, false)
  require('./sections/ack')('httpproxy plaintext', httpPlaintextSettings, false)
  require('./sections/ack')('fifo', fifoSettings, true)

  require('./sections/delete')('disk', {}, false)
  require('./sections/delete')('disk', {}, true)
  require('./sections/delete')('memory', {}, false)
  require('./sections/delete')('httpproxy json', httpJsonSettings, false)
  require('./sections/delete')('httpproxy plaintext', httpPlaintextSettings, false)
  require('./sections/delete')('fifo', fifoSettings, false)
  require('./sections/delete')('fifo', fifoSettings, true)

  require('./sections/health')('none', {}, false)
  require('./sections/health')('disk', {}, false)
  require('./sections/health')('memory', {}, false)
  require('./sections/health')('httpproxy json', httpJsonSettings, false)
  require('./sections/health')('httpproxy plaintext', httpPlaintextSettings, false)
  require('./sections/health')('elasticsearch', esSettings, true)
  require('./sections/health')('pubsub', pubsubSettings, true)
  require('./sections/health')('fifo', fifoSettings, false)

  require('./sections/none')('none', {}, false)
  require('./sections/pubsub')('pubsub', pubsubSettings, true)
  require('./sections/fifo')('fifo no-consumer', fifoSettings, true)
  require('./sections/httpproxy')('httpproxy no-consumer', httpJsonSettings, true)
  require('./sections/elasticsearch')('elasticsearch', esSettings, true)

  run()
})
