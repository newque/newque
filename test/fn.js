var request = require('superagent')

var base = 'http://127.0.0.1:'

var call = exports.call = function (method, port, path, buf, headers) {
  return new Promise(function (resolve, reject) {
    var req = request(method, base+port+path)

    if (headers) {
      req = headers.reduce(((r, h) => r.set(h[0], h[1])), req)
    }

    if (buf) {
      req.send(buf)
    }

    req.end(function (err, result) {
      if (result && result.res && result.res.statusCode > 0) {
        return resolve(result)
      }
      return reject(err)
    })
  })
}
