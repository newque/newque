'use strict'

global.Promise = require('bluebird')
global.Fn = require('./fn')
global.C = require('./constants')
global.Proc = require('./proc')
var newquePath = '../newque.native'
var localExecutable = './newque'

Proc.pathExists(newquePath)
.then(function (exists) {
  if (!exists) {
    throw new Error('Newque executable not found at ' + newquePath)
  }
  return Proc.copyFile(newquePath, localExecutable)
})
.then(function () {
  return Proc.chmod(localExecutable, '755')
})
.then(Proc.cleanDirectories)
.then(function () {
  require('./sections/count')('disk')
  require('./sections/count')('memory')

  require('./sections/push')('disk')
  require('./sections/push')('memory')

  require('./sections/pull')('disk')
  require('./sections/pull')('memory')

  require('./sections/ack')('disk')
  require('./sections/ack')('memory')
  run()
})
