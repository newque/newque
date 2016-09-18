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
  require('./sections/push')
  require('./sections/count')
  require('./sections/pull')
  run()
})
