var fs = require('fs')
var spawn = require('child_process').spawn
var exec = require('child_process').exec

var newquePath = exports.newquePath = __dirname + '/../newque.native'
var confDir = __dirname + '/conf'
var runningDir = __dirname + '/running'
var remoteRunningDir = __dirname + '/remoteRunning'
var remoteConfDir = __dirname + '/remoteConf'

var pathExists = exports.pathExists = function (path) {
  return Promise.promisify(fs.stat)(path)
  .then(stat => stat && stat.size > 0)
  .catch(function (err) {
    if (err && err.code === 'ENOENT') {
      err.message = 'File or directory not found: ' + path
    }
    return Promise.reject(err)
  })
}

var readDirectory = function (path) {
  return pathExists(path)
  .then(function (exists) {
    if (exists) {
      return Promise.promisify(fs.readdir)(path)
    } else {
      throw new Error('Nothing to read at ' + path)
    }
  })
}

var readFile = function (path) {
  return pathExists(path)
  .then(function (exists) {
    if (exists) {
      return Promise.promisify(fs.readFile)(path)
    } else {
      throw new Error('Nothing to read at ' + path)
    }
  })
}

var writeFile = function (path, data) {
  return Promise.promisify(fs.writeFile)(path, data)
}

var copyFile = exports.copyFile = function (from, to) {
  return new Promise(function (resolve, reject) {
    var rs = fs.createReadStream(from)
    var ws = fs.createWriteStream(to)
    rs.pipe(ws)
    rs.on('error', reject)
    ws.on('error', reject)
    rs.on('end', resolve)
  })
}

var copyDir = exports.copyDir = function (from, to) {
  return pathExists(from)
  .then(function (exists) {
    if (exists) {
      return Promise.promisify(exec)('cp -R ' + from + ' ' + to)
    } else {
      throw new Error('Nothing to copy at ' + path)
    }
  })
}

var createDir = exports.createDir = function (path) {
  return Promise.promisify(fs.mkdir)(path)
}

var rm = exports.rm = function (path) {
  return Promise.promisify(exec)('rm -rf ' + path)
}

var chmod = exports.chmod = function (path, mode) {
  return pathExists(path)
  .then(function (exists) {
    if (exists) {
      return Promise.promisify(fs.chmod)(path, mode)
      .then(() => Promise.resolve(true))
    } else {
      return Promise.resolve(false)
    }
  })
}

exports.cleanDirectories = function (arr) {
  return Promise.all([
    rm(runningDir)
  ])
}

var getEnvironment = function () {
  var path = runningDir + '/conf/'
  var env = {
    channels: {}
  }
  return readFile(path + 'newque.json')
  .then(function (contents) {
    env.newque = JSON.parse(contents)
    return Promise.map(readDirectory(path + 'channels'), c => readFile(path + 'channels/' + c))
  })
  .then(function (channels) {
    channels.forEach(c => env.channels[c] = JSON.parse(c))
    return Promise.resolve(env)
  })
}

exports.setupEnvironment = function (persistence, persistenceSettings) {
  var type = persistence.split(' ')[0]
  var remoteType = persistence.split(' ')[1]
  return rm(remoteRunningDir)
  .then(() => createDir(remoteRunningDir))
  .then(() => copyDir(remoteConfDir, remoteRunningDir + '/conf'))
  .then(() => readDirectory(confDir + '/channels'))
  .then(function (channels) {
    return Promise.all(channels.map(function (channel) {
      return readFile(confDir + '/channels/' + channel)
      .then(function (contents) {
        var parsed = JSON.parse(contents.toString('utf8'))
        parsed.persistence = 'memory'
        if (parsed.readSettings) {
          parsed.readSettings.format = remoteType
        }
        if (parsed.writeSettings) {
          parsed.writeSettings.format = remoteType
          delete parsed.writeSettings.batching
        }
        return writeFile(remoteRunningDir + '/conf/channels/' + channel, JSON.stringify(parsed, null, 2))
      })
    }))
  })
  .then(() => rm(runningDir))
  .then(() => createDir(runningDir))
  .then(() => copyDir(confDir, runningDir + '/conf'))
  .then(() => readDirectory(confDir + '/channels'))
  .then(function (channels) {
    return Promise.all(channels.map(function (channel) {
      return readFile(confDir + '/channels/' + channel)
      .then(function (contents) {
        var parsed = JSON.parse(contents.toString('utf8'))
        parsed.persistence = type
        if (parsed.persistenceSettings == null) {
          parsed.persistenceSettings = persistenceSettings
        } else {
          for (var key in persistenceSettings) {
            parsed.persistenceSettings[key] = persistenceSettings[key]
          }
        }
        return writeFile(runningDir + '/conf/channels/' + channel, JSON.stringify(parsed, null, 2))
      })
    }))
  })
  .then(function () {
    var processes = [spawnExecutable(newquePath, runningDir)]
    if (type === 'http') {
      processes.push(spawnExecutable(newquePath, remoteRunningDir))
    }
    return Promise.resolve(processes)
  })
}

var spawnExecutable = exports.spawnExecutable = function (execLocation, dirLocation) {
  var debug = process.env.DEBUG === '1'
  var p = spawn(execLocation, [], {
    cwd: dirLocation,
    detached: false
  })
  p.stderr.on('data', function (data) {
    console.log(data.toString('utf8'))
    throw new Error('STDERR output detected')
  })
  p.stderr.on('err', function (err) {
    console.log(err)
    throw new Error('STDERR disconnected')
  })
  p.stdout.on('err', function (err) {
    console.log(err)
    throw new Error('STDOUT disconnected')
  })
  if (debug) {
    p.stdout.on('data', function (data) {
      console.log(data.toString('utf8'))
    })
  }
  return p
}

exports.teardown = function (processes) {
  processes.forEach((p) => p.kill())
}
