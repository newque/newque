module.exports = function (backend, backendSettings, raw) {
  describe('Count ' + backend + (!!raw ? ' raw' : ''), function () {
    if (backend === 'elasticsearch') {
      var delay = C.esDelay
      this.timeout(C.esTimeout)
    } else {
      var delay = 0
    }
    var env
    before(function () {
      this.timeout(C.setupTimeout)
      return Proc.setupEnvironment(backend, backendSettings, raw)
      .then(function (pEnv) {
        env = pEnv
        return Promise.delay(C.spawnDelay)
      })
    })
    beforeEach(function () {
      Scenarios.clear()
    })

    it('Valid', function () {
      var buf = `{"a":"abc"}\n{"a":"def"}\n{"a":"ghi"}\n{"a":"jkl"}`
      return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'multiple']])
      .then(Fn.shouldHaveWritten(4))
      .delay(delay)
      .then(() => Fn.call('GET', 8000, '/v1/example/count'))
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
      it('Should count', function () {
        return Fn.call('GET', 8000, '/v1/writeonly/count')
        .then(Fn.shouldHaveCounted(0))
      })
    })

    after(function () {
      this.timeout(C.esTimeout)
      return Proc.teardown(env, backend, backendSettings)
    })
  })
}
