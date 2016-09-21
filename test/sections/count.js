module.exports = function (id) {
  describe('Count ' + id, function () {
    var p, env
    before(function () {
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
    })

    it('Valid', function () {
      var buf = ''
      return Fn.call('GET', 8000, '/v1/example/count', buf)
      .then(Fn.shouldHaveCounted(4))
    })

    it('Valid, empty', function () {
      var buf = ''
      return Fn.call('GET', 8000, '/v1/empty/count', buf)
      .then(Fn.shouldHaveCounted(0))
    })

    it('Invalid path', function () {
      var buf = ''
      return Fn.call('GET', 8000, '/v1//count', buf)
      .then(Fn.shouldFail(400))
    })

    it('Invalid path 2', function () {
      var buf = ''
      return Fn.call('GET', 8000, '/v1/nothing/count', buf)
      .then(Fn.shouldFail(400))
    })

    it('Invalid method', function () {
      var buf = ''
      return Fn.call('XYZ', 8000, '/v1/example/count', buf)
      .then(Fn.shouldFail(405))
    })

    after(function () {
      return Proc.stopExecutable(p)
    })
  })
}
