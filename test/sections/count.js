module.exports = function (persistence) {
  describe('Count ' + persistence, function () {
    var p, env
    before(function () {
      return Proc.setupEnvironment(persistence)
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
      return Fn.call('GET', 8000, '/v1/example/count')
      .then(Fn.shouldHaveCounted(4))
    })

    it('Valid, empty', function () {
      return Fn.call('GET', 8000, '/v1/empty/count')
      .then(Fn.shouldHaveCounted(0))
    })

    it('Invalid path', function () {
      return Fn.call('GET', 8000, '/v1//count')
      .then(Fn.shouldFail(400))
    })

    it('Invalid path 2', function () {
      return Fn.call('GET', 8000, '/v1/nothing/count')
      .then(Fn.shouldFail(400))
    })

    it('Invalid method', function () {
      return Fn.call('XYZ', 8000, '/v1/example/count')
      .then(Fn.shouldFail(405))
    })

    describe('Read only', function () {
      it('Should count', function () {
        return Fn.call('GET', 8000, '/v1/readonly/count')
      .then(Fn.shouldHaveCounted(0))
      })
    })

    describe('Write only', function () {
      it('Should not count', function () {
        return Fn.call('GET', 8000, '/v1/writeonly/count')
        .then(Fn.shouldFail(400))
      })
    })

    after(function () {
      return Proc.stopExecutable(p)
    })
  })
}
