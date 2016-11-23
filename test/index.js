'use strict'

global.Promise = require('bluebird')
global.Fn = require('./fn')
global.C = require('./constants')
global.Proc = require('./proc')

Proc.pathExists(Proc.newquePath)
.then(function (exists) {
  if (!exists) {
    throw new Error('Newque executable not found at ' + Proc.newquePath)
  }
})
.then(Proc.cleanDirectories)
.then(function (server) {

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

  require('./sections/count')('disk', {})
  require('./sections/count')('memory', {})
  require('./sections/count')('http json', httpJsonSettings)
  require('./sections/count')('http plaintext', httpPlaintextSettings)
  require('./sections/count')('disk', {}, true)
  require('./sections/count')('elasticsearch', esSettings, true)

  require('./sections/push')('disk', {})
  require('./sections/push')('memory', {})
  require('./sections/push')('http json', httpJsonSettings)
  require('./sections/push')('http plaintext', httpPlaintextSettings)
  require('./sections/push')('http json', httpJsonSettings, true)
  require('./sections/push')('http plaintext', httpPlaintextSettings, true)
  require('./sections/push')('disk', {}, true)
  require('./sections/push')('elasticsearch', esSettings, true)

  require('./sections/pull')('disk', {})
  require('./sections/pull')('memory', {})
  require('./sections/pull')('http json', httpJsonSettings)
  require('./sections/pull')('http plaintext', httpPlaintextSettings)
  require('./sections/pull')('http json', httpJsonSettings, true)
  require('./sections/pull')('http plaintext', httpPlaintextSettings, true)
  require('./sections/pull')('disk', {}, true)

  require('./sections/ack')('disk', {})
  require('./sections/ack')('memory', {})
  require('./sections/ack')('http json', httpJsonSettings)
  require('./sections/ack')('http plaintext', httpPlaintextSettings)
  require('./sections/ack')('disk', {}, true)

  require('./sections/health')('disk', {})
  require('./sections/health')('memory', {})
  require('./sections/health')('http json', httpJsonSettings)
  require('./sections/health')('http plaintext', httpPlaintextSettings)
  require('./sections/health')('elasticsearch', esSettings, true)
  run()
})
