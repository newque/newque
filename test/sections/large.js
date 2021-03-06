module.exports = function (backend, backendSettings, raw) {
  describe('LargeBatches ' + backend + (!!raw ? ' raw' : ''), function () {
    var overrideBackendSettings = JSON.parse(JSON.stringify(backendSettings))
    var delay = 0
    this.timeout(5000)

    if (backend === 'elasticsearch') {
      delay = C.esDelay
      this.timeout(C.esTimeout)
    } else if (backend === 'redis') {
      delay = 50
    } else if (backend === 'fifo') {
      overrideBackendSettings.timeout = 5000
    } else if (backend.split(' ').slice(0, 1)[0] === 'httpproxy') {
      overrideBackendSettings.timeout = 5000
    }

    var env
    before(function () {
      this.timeout(C.setupTimeout)
      return Proc.setupEnvironment(backend, overrideBackendSettings, raw)
      .then(function (pEnv) {
        env = pEnv
        return Promise.delay(C.spawnDelay)
      })
    })
    beforeEach(function () {
      Scenarios.clear()
    })

    var makeMessage = function (len, sep) {
      var skip = sep.charCodeAt(0)
      var buf = new Buffer(len)
      for (var i = 0; i < len; i++) {
        buf[i] = i % 128 !== skip ? i % 128 : 0
      }
      return buf
    }

    var makeMessageAscii = function (len) {
      var buf = new Buffer(len)
      for (var i = 0; i < len; i++) {
        buf[i] = (i % 26) + 65
      }
      return buf
    }

    var wrapInJon = function (buf) {
      return new Buffer(JSON.stringify({x: buf.toString('utf8')}), 'utf8')
    }

    var makeMessages = function (bufs, sep) {
      var arr = []
      var sepBuf = new Buffer(sep, 'utf8')
      for (var i = 0; i < bufs.length; i++) {
        arr.push(bufs[i])
        arr.push(sepBuf)
      }
      arr.pop()
      return Buffer.concat(arr)
    }

    var counter = 0

    var runTest = function (num, len) {
      Scenarios.set('large', 'last_id', 'someID')
      Scenarios.set('large', 'last_timens', 999)
      var sep = '\n'
      var msg = backend === 'elasticsearch' ? wrapInJon(makeMessageAscii(len)) : makeMessage(len, sep)
      var msgs = Array(num).fill(msg)
      var buf = makeMessages(msgs, sep).toString('utf8')
      counter += num

      return Fn.call('POST', 8000, '/v1/large', buf, [[C.modeHeader, 'multiple']])
      .then(Fn.shouldHaveWritten(num))
      .delay(delay)
      .then(function () {
        if (C.noCount.indexOf(backend) >= 0) {
          return Promise.resolve()
        } else {
          return Fn.call('GET', 8000, '/v1/large/count')
          .then(Fn.shouldHaveCounted(C.noRead.indexOf(backend) >= 0 ? counter : num))
        }
      })
      .then(() => {
        if (C.noRead.indexOf(backend) >= 0) {
          return Promise.resolve()
        } else {
          return Fn.call('GET', 8000, '/v1/large', null, [[C.modeHeader, 'many ' + num]])
          .then(Fn.shouldHaveRead(Array(num).fill(msg), sep))
        }
      })
    }

    describe('Increasing message size', function () {
      it('100x 10b (' + delay + 'ms delay)', function () {
        return runTest(100, 10)
      })

      it('100x 1Kb (' + delay + 'ms delay)', function () {
        return runTest(100, 1024)
      })

      it('100x 10Kb (' + delay + 'ms delay)', function () {
        return runTest(100, 10*1024)
      })

      it('100x 100Kb (' + delay + 'ms delay)', function () {
        return runTest(100, 100*1024)
      })

      it('2x 1Mb (' + delay + 'ms delay)', function () {
        return runTest(2, 1024*1024)
      })
    })

    describe('Increasing number of messages', function () {
      it('500x 10b (' + delay + 'ms delay)', function () {
        return runTest(500, 10)
      })

      it('1000x 10b (' + delay + 'ms delay)', function () {
        return runTest(1000, 10)
      })

      it('10,000x 10b (' + delay + 'ms delay)', function () {
        return runTest(10*1000, 10)
      })

      it('25,000x 10b (' + delay + 'ms delay)', function () {
        return runTest(25*1000, 10)
      })

      it('50,000x 10b (' + delay + 'ms delay)', function () {
        return runTest(50*1000, 10)
      })
    })


    after(function () {
      this.timeout(C.esTimeout)
      return Proc.teardown(env, backend, backendSettings)
    })
  })
}
