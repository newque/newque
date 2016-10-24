var fs = require('fs')
var spawn = require('child_process').spawn
var exec = require('child_process').exec

var localExecutable = __dirname + '/newque'
var confDir = __dirname + '/conf'
var runningDir = __dirname + '/running'

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

exports.setupEnvironment = function (persistence) {
  var path = runningDir + '/conf'
  return rm(runningDir)
  .then(() => createDir(runningDir))
  .then(() => copyDir(confDir, path))
  .then(() => readDirectory(confDir + '/channels'))
  .then(function (channels) {
    return Promise.all(channels.map(function (channel) {
      return readFile(confDir + '/channels/' + channel)
      .then(function (contents) {
        var parsed = JSON.parse(contents.toString('utf8'))
        parsed.persistence = persistence
        return writeFile(path + '/channels/' + channel, JSON.stringify(parsed, null, 2))
      })
    }))
  })
  .then(() => getEnvironment())
}

exports.spawnExecutable = function () {
  var debug = process.env.DEBUG === '1'
  var p = spawn(localExecutable, [], {
    cwd: runningDir,
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

exports.stopExecutable = function (p) {
  p.kill()
}
