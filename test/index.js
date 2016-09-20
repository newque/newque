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
  require('./sections/push')('disk1')
  require('./sections/push')('memory1')

  require('./sections/count')('disk1')
  require('./sections/count')('memory1')

  require('./sections/pull')('disk1')
  require('./sections/pull')('memory1')
  run()
})
