var request = require('superagent')
var assert = exports.assert = require('assert')
var base = 'http://127.0.0.1:'

var call = exports.call = function (method, port, path, buf, headers) {
  return new Promise(function (resolve, reject) {
    var req = request(method, base+port+path)
    if (headers) {
      headers.forEach(function (pair) {
        req.set(pair[0], pair[1])
      })
    }
    if (buf) {
      req.send(buf)
    }
    req.end(function (err, result) {
      if (result.res.headers['content-type'] === 'application/octet-stream') {
        var arr = []
        result.res.on('data', data => arr.push(data))
        result.res.on('end', function () {
          result.res.buffer = Buffer.concat(arr)
          return resolve(result)
        })
      } else if (result && result.res && result.res.statusCode > 0) {
        return resolve(result)
      } else {
        return reject(err)
      }
    })
  })
}

var shouldHaveWritten = exports.shouldHaveWritten = function (count) {
  return function (result) {
    return new Promise(function (resolve, reject) {
      assert(result.res.statusCode === 201)
      assert(result.body.code === 201)
      assert(result.body.errors.length === 0)
      assert(result.body.saved === count)
      return resolve(result)
    })
    .catch(function (err) {
      console.log(result.res.statusCode)
      console.log(result.body)
      throw err
    })
  }
}

var shouldHaveWrittenAsync = exports.shouldHaveWrittenAsync = function () {
  return function (result) {
    return new Promise(function (resolve, reject) {
      assert(result.res.statusCode === 202)
      assert(result.body.code === 202)
      assert(result.body.errors.length === 0)
      assert(result.body.saved == null)
      return resolve(result)
    })
    .catch(function (err) {
      console.log(result.res.statusCode)
      console.log(result.body)
      throw err
    })
  }
}

var shouldHaveCounted = exports.shouldHaveCounted = function (count) {
  return function (result) {
    return new Promise(function (resolve, reject) {
      assert(result.res.statusCode === 200)
      assert(result.body.code === 200)
      assert(result.body.errors.length === 0)
      assert(result.body.count === count)
      return resolve(result)
    })
    .catch(function (err) {
      console.log(result.res.statusCode)
      console.log(result.body)
      throw err
    })
  }
}

var shouldHaveRead = exports.shouldHaveRead = function (values, separator) {
  return function (result) {
    // console.log(result.res.statusCode)
    // console.log(result.res.text)
    return new Promise(function (resolve, reject) {
      if (values.length === 0) {
        assert(result.res.statusCode === 204)
      } else {
        assert(result.res.statusCode === 200)
        var sep = new Buffer(separator, 'utf8')
        var arr = []
        if (Buffer.isBuffer(values[0])) {
          values.forEach(v => arr.push(v, sep))
        } else {
          values.forEach(v => arr.push(new Buffer(v, 'utf8'), sep))
        }
        assert(arr.length === values.length * 2)
        arr.pop()
        var buf = Buffer.concat(arr)
        // console.log('Expecting', JSON.stringify(buf.toString('utf8')))
        // console.log('Got', JSON.stringify(result.res.buffer.toString('utf8')))
        assert(Buffer.compare(buf, result.res.buffer) === 0)
      }

      // Check HTTP headers
      if (result.res.headers['transfer-encoding'] === 'chunked') {
        assert(result.res.headers['content-length'] == null)
        assert(result.res.headers[C.lengthHeader] == null)
      } else {
        if (result.res.statusCode === 200) {
          assert(parseInt(result.res.headers[C.lengthHeader], 10) === values.length)
          assert(parseInt(result.res.headers['content-length'], 10) === result.res.buffer.length)
          assert(result.res.headers[C.lastIdHeader].length > 0)
          assert(parseInt(result.res.headers[C.lastTsHeader], 10) > 0)
        } else if (result.res.statusCode === 204) {
          assert(result.res.headers['content-length'] == null)
          assert(parseInt(result.res.headers[C.lengthHeader], 10) === 0)
        }
      }
      return resolve(result)
    })
  }
}

var shouldFail = exports.shouldFail = function (code) {
  return function (result) {
    return new Promise(function (resolve, reject) {
      assert(result.res.statusCode === code)
      assert(result.body.code === code)
      assert(result.body.errors.length > 0)
      return resolve()
    })
    .catch(function (err) {
      console.log(result.res.statusCode)
      console.log(result.body)
      throw err
    })
  }
}
