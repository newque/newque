var request = require('superagent')
var assert = exports.assert = require('assert')
var base = 'http://127.0.0.1:'

var call = exports.call = function (method, port, path, buf, headers) {
  var t0 = Date.now()
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
      if (result && result.res && result.res.statusCode > 0) {
        if (result.res.headers['content-type'] === 'application/json') {
          result.res.buffer = new Buffer(JSON.stringify(result.body), 'utf8')
          return resolve(result)
        }
        var arr = []
        result.res.on('data', data => arr.push(data))
        result.res.on('end', function () {
          result.res.buffer = Buffer.concat(arr)
          return resolve(result)
        })
      } else {
        return reject(err)
      }
    })
  })
  .catch(function (err) {
    console.log('Fn.call ERROR!!!')
    console.log(method, port, path, headers)
    // console.log(buf)
    console.log(err.stack)
    return Promise.reject(err)
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
    // console.log(result.res.headers)
    return new Promise(function (resolve, reject) {
      assert(result.res.statusCode === 200)

      if (separator !== null) {
        // PLAINTEXT BODY
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
      } else {
        // JSON BODY
        var json = {
          code: 200,
          errors: [],
          messages: values
        }
        var buf = new Buffer(JSON.stringify(json), 'utf8')
      }

      if (Buffer.compare(buf, result.res.buffer) !== 0) {
        console.log('Expecting', JSON.stringify(buf.toString('utf8')))
        console.log('Got', JSON.stringify(result.res.buffer.toString('utf8')))
        return reject(new Error('Invalid response buffer'))
      }

      // Check HTTP headers
      if (result.res.headers['transfer-encoding'] === 'chunked') {
        assert(result.res.headers['content-length'] == null)
      } else {
        assert(parseInt(result.res.headers[C.lengthHeader], 10) === values.length)
        assert(parseInt(result.res.headers['content-length'], 10) === result.res.buffer.length)
        if (parseInt(result.res.headers[C.lengthHeader], 10) > 0) {
          assert(result.res.headers[C.lastIdHeader] != null)
          assert(parseInt(result.res.headers[C.lastTsHeader], 10) > 0)
        }
      }
      return resolve(result)
    })
    .catch(function (err) {
      console.log(result.res.statusCode)
      console.log(result.body)
      console.log(result.res.headers)
      throw err
    })
  }
}

var shouldFail = exports.shouldFail = function (code) {
  return function (result) {
    return new Promise(function (resolve, reject) {
      assert(result.res.statusCode === code)
      assert(result.body.code === code)
      assert(result.body.errors.length > 0)
      return resolve(result)
    })
    .catch(function (err) {
      console.log(result.res.statusCode)
      console.log(result.body)
      throw err
    })
  }
}

var shouldReturn = exports.shouldReturn = function (code, json) {
  return function (result) {
    return new Promise(function (resolve, reject) {
      assert(result.res.statusCode === code)
      assert(result.body.code === code)
      assert(JSON.stringify(result.body) === JSON.stringify(json))
      return resolve(result)
    })
    .catch(function (err) {
      console.log(result.res.statusCode)
      console.log(result.body)
      throw err
    })
  }
}

var makeJsonBuffer = exports.makeJsonBuffer = function (arr, ids, atomic) {
  var payload = {
    messages: arr
  }
  if (ids && ids.length > 0) { payload.ids = ids }
  if (atomic) { payload.atomic = true }
  return JSON.stringify(payload)
}
