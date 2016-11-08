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

  require('./sections/count')('disk', {})
  require('./sections/count')('memory', {})

  require('./sections/push')('disk', {})
  require('./sections/push')('memory', {})

  require('./sections/pull')('disk', {})
  require('./sections/pull')('memory', {})

  require('./sections/ack')('disk', {})
  require('./sections/ack')('memory', {})
  require('./sections/ack')('http json', httpJsonSettings)
  require('./sections/ack')('http plaintext', httpPlaintextSettings)
  run()
})
