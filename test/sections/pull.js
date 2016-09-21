module.exports = function (id) {
  describe('Pull ' + id, function () {
    var p, env
    before(function () {
      this.timeout(10000)
      return Proc.setupEnvironment(id)
      .then(function (environment) {
        env = environment
        p = Proc.spawnExecutable()
        return Promise.delay(C.spawnDelay)
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
    })

    it('Without header, secondary channel', function () {
      return Fn.call('GET', 8000, '/v1/secondary')
      .then(Fn.shouldFail(400))
    })

    it('Without header', function () {
      return Fn.call('GET', 8000, '/v1/example')
      .then(Fn.shouldFail(400))
    })

    it('One', function () {
      return Fn.call('GET', 8000, '/v1/example', null, [[C.modeHeader, 'one']])
      .then(Fn.shouldHaveRead(['M abc'], '\n'))
    })

    it('One, secondary channel', function () {
      return Fn.call('GET', 8000, '/v1/secondary', null, [[C.modeHeader, 'one']])
      .then(Fn.shouldHaveRead(['XYZ'], '\n'))
    })

    it('Many, smaller than count', function () {
      return Fn.call('GET', 8000, '/v1/example', null, [[C.modeHeader, 'Many 3']])
      .then(Fn.shouldHaveRead(['M abc', 'M def', 'M ghi'], '\n'))
    })

    it('Many, greater than count', function () {
      return Fn.call('GET', 8000, '/v1/example', null, [[C.modeHeader, 'Many 30']])
      .then(Fn.shouldHaveRead(['M abc', 'M def', 'M ghi', 'M jkl'], '\n'))
    })

    it('Many, secondary channel', function () {
      return Fn.call('GET', 8000, '/v1/secondary', null, [[C.modeHeader, 'many 3']])
      .then(Fn.shouldHaveRead(['XYZ', 'ABCD', ''], '--'))
    })

    it('Many, empty channel', function () {
      return Fn.call('GET', 8000, '/v1/empty', null, [[C.modeHeader, 'many 10']])
      .then(Fn.shouldHaveRead([], '\n'))
    })

    describe('HTTP Transport', function () {
      it('Fixed length by default', function () {
        return Fn.call('GET', 8000, '/v1/example', null, [[C.modeHeader, 'many 30']])
        .then(Fn.shouldHaveRead(['M abc', 'M def', 'M ghi', 'M jkl'], '\n'))
        .then(function (result) {
          Fn.assert(parseInt(result.res.headers['content-length'], 10) === result.res.buffer.length)
        })
      })

      it('Chunked when requested', function () {
        return Fn.call('GET', 8000, '/v1/example', null, [[C.modeHeader, 'many 30'], ['Transfer-Encoding', 'chunked']])
        .then(Fn.shouldHaveRead(['M abc', 'M def', 'M ghi', 'M jkl'], '\n'))
        .then(function (result) {
          Fn.assert(result.res.headers['content-length'] == null)
          Fn.assert(result.res.headers['transfer-encoding'] == 'chunked')
        })
      })
    })

    after(function () {
      return Proc.stopExecutable(p)
    })
  })
}
