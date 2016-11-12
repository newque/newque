module.exports = function (persistence, persistenceSettings) {
  describe('Pull ' + persistence, function () {
    var processes = []
    before(function () {
      this.timeout(10000)
      return Proc.setupEnvironment(persistence, persistenceSettings)
      .then(function (procs) {
        procs.forEach((p) => processes.push(p))
        return Promise.delay(C.spawnDelay * processes.length)
      })
      .then(function () {
        var buf = 'M abc\nM def\nM ghi\nM jkl'
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'multiple']])
        .then(Fn.shouldHaveWritten(4))
      })
      .then(function () {
        var buf = 'XYZ--ABCD--'
        return Fn.call('POST', 8000, '/v1/secondary', buf, [[C.modeHeader, 'multiple']])
        .then(Fn.shouldHaveWritten(3))
      })
      .then(function () {
        var buf = Fn.makeJsonBuffer(['123', '456', ''])
        return Fn.call('POST', 8000, '/v1/json', buf, [[C.modeHeader, 'multiple']])
        .then(Fn.shouldHaveWritten(3))
      })
    })

    var transports = [
      {name: 'Fixed-Length', headers: []},
      {name: 'Chunked', headers: [['Transfer-Encoding', 'chunked']]}
    ]
    for (var i = 0; i < transports.length; i++) {
      describe('Transfer-Encoding: ' + transports[i].name, function () {
        var ii = i
        it('Without header, secondary channel', function () {
          return Fn.call('GET', 8000, '/v1/secondary', null, transports[ii].headers)
          .then(Fn.shouldFail(400))
        })

        it('Without header', function () {
          return Fn.call('GET', 8000, '/v1/example', null, transports[ii].headers)
          .then(Fn.shouldFail(400))
        })

        it('One', function () {
          return Fn.call('GET', 8000, '/v1/example', null, [[C.modeHeader, 'one']].concat(transports[ii].headers))
          .then(Fn.shouldHaveRead(['M abc'], '\n'))
        })

        it('One, secondary channel', function () {
          return Fn.call('GET', 8000, '/v1/secondary', null, [[C.modeHeader, 'one']].concat(transports[ii].headers))
          .then(Fn.shouldHaveRead(['XYZ'], '\n'))
        })

        it('Many, smaller than count', function () {
          return Fn.call('GET', 8000, '/v1/example', null, [[C.modeHeader, 'Many 3']].concat(transports[ii].headers))
          .then(Fn.shouldHaveRead(['M abc', 'M def', 'M ghi'], '\n'))
        })

        it('Many, greater than count', function () {
          return Fn.call('GET', 8000, '/v1/example', null, [[C.modeHeader, 'Many 30']].concat(transports[ii].headers))
          .then(Fn.shouldHaveRead(['M abc', 'M def', 'M ghi', 'M jkl'], '\n'))
        })

        it('Many, secondary channel (max read, different separator)', function () {
          return Fn.call('GET', 8000, '/v1/secondary', null, [[C.modeHeader, 'many 3']].concat(transports[ii].headers))
          .then(Fn.shouldHaveRead(['XYZ', 'ABCD'], '--'))
        })

        it('Many, empty channel', function () {
          return Fn.call('GET', 8000, '/v1/empty', null, [[C.modeHeader, 'many 10']].concat(transports[ii].headers))
          .then(Fn.shouldHaveRead([], '\n'))
        })


        describe('Read only', function () {
          it('Should pull', function () {
            return Fn.call('GET', 8000, '/v1/readonly', null, [[C.modeHeader, 'one']].concat(transports[ii].headers))
            .then(Fn.shouldHaveRead([], '\n'))
          })
        })

        describe('Write only', function () {
          it('Should not pull', function () {
            return Fn.call('GET', 8000, '/v1/writeonly', null, [[C.modeHeader, 'one']].concat(transports[ii].headers))
            .then(Fn.shouldFail(400))
          })
        })
      })
    }

    describe('JSON', function () {
      it('Many', function () {
        return Fn.call('GET', 8000, '/v1/json', null, [[C.modeHeader, 'many 3']])
        .then(Fn.shouldHaveRead(['123', '456', ''], null))
      })

      it('Empty', function () {
        return Fn.call('GET', 8000, '/v1/json', null, [[C.modeHeader, 'after_id thisdoesntexist']])
        .then(Fn.shouldHaveRead([], null))
      })
    })

    // This only works on non-stream
    it('After_id', function () {
      return Fn.call('GET', 8000, '/v1/example', null, [[C.modeHeader, 'one']])
      .then(Fn.shouldHaveRead(['M abc'], '\n'))
      .then(function (result) {
        var lastId = result.res.headers[C.lastIdHeader]
        return Fn.call('GET', 8000, '/v1/example', null, [[C.modeHeader, 'after_id ' + lastId]])
      })
      .then(Fn.shouldHaveRead(['M def', 'M ghi', 'M jkl'], '\n'))
    })

    // This only works on non-stream
    it('After_ts', function () {
      var lastTs = null
      return Fn.call('GET', 8000, '/v1/example', null, [[C.modeHeader, 'one']])
      .then(Fn.shouldHaveRead(['M abc'], '\n'))
      .then(function (result) {
        lastTs = parseInt(result.res.headers[C.lastTsHeader], 10)
        // All added in the same batch, so it should return nothing
        return Fn.call('GET', 8000, '/v1/example', null, [[C.modeHeader, 'After_ts ' + lastTs]])
      })
      .then(Fn.shouldHaveRead([], '\n'))
      .then(function () {
        // Removing a 1 nanosecond will return all of them, but JS numbers don't have enough precision
        // at that scale, so we remove more
        return Fn.call('GET', 8000, '/v1/example', null, [[C.modeHeader, 'After_ts ' + (lastTs - 1000)]])
      })
      .then(Fn.shouldHaveRead(['M abc', 'M def', 'M ghi', 'M jkl'], '\n'))
    })

    describe('Only Once', function () {
      it('Should delete after reading (sync)', function () {
        var buf = Fn.makeJsonBuffer(['abc', 'def', 'ghi', 'jkl'])
        return Fn.call('POST', 8000, '/v1/onlyOnce', buf, null)
        .then(Fn.shouldHaveWritten(4))
        .then(() => Fn.call('GET', 8000, '/v1/onlyOnce', null, [[C.modeHeader, 'One']]))
        .then(Fn.shouldHaveRead(['abc'], null))
        .then(() => Fn.call('GET', 8000, '/v1/onlyOnce', null, [[C.modeHeader, 'One']]))
        .then(Fn.shouldHaveRead(['def'], null))
        .then(() => Fn.call('GET', 8000, '/v1/onlyOnce', null, [[C.modeHeader, 'Many 2']]))
        .then(Fn.shouldHaveRead(['ghi', 'jkl'], null))
        .then(() => Fn.call('GET', 8000, '/v1/onlyOnce', null, [[C.modeHeader, 'One']]))
        .then(Fn.shouldHaveRead([], null))
      })

      it('Should delete after reading (async)', function () {
        var buf = Fn.makeJsonBuffer(['ABC', 'DEF', 'GHI', 'JKL'])
        return Fn.call('POST', 8000, '/v1/onlyOnce', buf, null)
        .then(function () {
          return Promise.map([
            // maxRead for the channel is set to 2
            Fn.call('GET', 8000, '/v1/onlyOnce', null, [[C.modeHeader, 'Many 5']]),
            Fn.call('GET', 8000, '/v1/onlyOnce', null, [[C.modeHeader, 'Many 5']]),
            Fn.call('GET', 8000, '/v1/onlyOnce', null, [[C.modeHeader, 'Many 5']]),
            Fn.call('GET', 8000, '/v1/onlyOnce', null, [[C.modeHeader, 'Many 5']])
          ],
          function (result) {
            if (result.res.buffer.length > 0) {
              var msgs = JSON.parse(result.res.buffer.toString('utf8')).messages
              if (JSON.stringify(msgs) === JSON.stringify(['ABC', 'DEF'])) {
                return Fn.shouldHaveRead(['ABC', 'DEF'], null)(result)
                .then(() => msgs)
              } else {
                return Fn.shouldHaveRead(['GHI', 'JKL'], null)(result)
                .then(() => msgs)
              }
            } else {
              return Fn.shouldHaveRead([], null)(result)
              .then(() => [])
            }
          })
        })
        .then(function (arrays) {
          var arr = Array.prototype.concat.apply([], arrays).sort()
          Fn.assert(JSON.stringify(arr) === JSON.stringify(['ABC', 'DEF', 'GHI', 'JKL']))
        })
      })
    })

    after(function () {
      return Proc.teardown(processes)
    })
  })
}
