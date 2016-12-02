'use strict'

global.Promise = require('bluebird')
global.Fn = require('./fn')
global.C = require('./constants')
global.Proc = require('./proc')

var httpJsonSettings = {
  baseUrls: ['http://127.0.0.1:' + C.remotePort + '/v1/'],
  baseHeaders: [{key: 'secret-token', value: 'supersecret'}],
  appendChannelName: true
}
var httpPlaintextSettings = {
  baseUrls: ['http://127.0.0.1:' + C.remotePort + '/v1/'],
  baseHeaders: [{key: 'secret-token', value: 'supersecret'}],
  appendChannelName: true,
  remoteInputFormat: 'plaintext',
  remoteOutputFormat: 'plaintext'
}
var esSettings = {
  baseUrls: ['http://127.0.0.1:9200'],
  // index is configured in the setup
  type: 'test-type'
}

Proc.pathExists(Proc.newquePath)
.then(function (exists) {
  if (!exists) {
    throw new Error('Newque executable not found at ' + Proc.newquePath)
  }
})
.then(Proc.clearEs(esSettings))
.then(function (server) {

  require('./sections/count')('disk', {})
  require('./sections/count')('memory', {})
  require('./sections/count')('remotehttp json', httpJsonSettings)
  require('./sections/count')('remotehttp plaintext', httpPlaintextSettings)
  require('./sections/count')('disk', {}, true)
  require('./sections/count')('elasticsearch', esSettings, true)

  require('./sections/push')('disk', {})
  require('./sections/push')('memory', {})
  require('./sections/push')('remotehttp json', httpJsonSettings)
  require('./sections/push')('remotehttp plaintext', httpPlaintextSettings)
  require('./sections/push')('remotehttp json', httpJsonSettings, true)
  require('./sections/push')('remotehttp plaintext', httpPlaintextSettings, true)
  require('./sections/push')('disk', {}, true)
  require('./sections/push')('elasticsearch', esSettings, true)

  require('./sections/pull')('disk', {})
  require('./sections/pull')('memory', {})
  require('./sections/pull')('remotehttp json', httpJsonSettings)
  require('./sections/pull')('remotehttp plaintext', httpPlaintextSettings)
  require('./sections/pull')('remotehttp json', httpJsonSettings, true)
  require('./sections/pull')('remotehttp plaintext', httpPlaintextSettings, true)
  require('./sections/pull')('disk', {}, true)

  require('./sections/ack')('disk', {})
  require('./sections/ack')('memory', {})
  require('./sections/ack')('remotehttp json', httpJsonSettings)
  require('./sections/ack')('remotehttp plaintext', httpPlaintextSettings)
  require('./sections/ack')('disk', {}, true)

  require('./sections/delete')('disk', {})
  require('./sections/delete')('memory', {})
  require('./sections/delete')('remotehttp json', httpJsonSettings)
  require('./sections/delete')('remotehttp plaintext', httpPlaintextSettings)
  require('./sections/delete')('disk', {}, true)

  require('./sections/health')('disk', {})
  require('./sections/health')('memory', {})
  require('./sections/health')('remotehttp json', httpJsonSettings)
  require('./sections/health')('remotehttp plaintext', httpPlaintextSettings)
  require('./sections/health')('elasticsearch', esSettings, true)

  run()
})
