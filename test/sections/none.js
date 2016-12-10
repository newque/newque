module.exports = function (backend, backendSettings, raw) {
  describe('None', function () {
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

    it('Push', function () {
      var buf = `{"a":"abc"}\n{"a":"def"}\n{"a":"ghi"}\n{"a":"jkl"}`
      return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'multiple']])
      .then(Fn.shouldHaveWritten(0))
    })

    it('Pull', function () {
      return Fn.call('GET', 8000, '/v1/example', null, [[C.modeHeader, 'one']])
      .then(Fn.shouldHaveRead([], '\n'))
    })

    it('Count', function () {
      return Fn.call('GET', 8000, '/v1/example/count')
      .then(Fn.shouldHaveCounted(0))
    })

    it('Delete', function () {
      Fn.call('DELETE', 8000, '/v1/example')
      .then(Fn.shouldReturn(200, {code:200, errors:[]}))
    })

    after(function () {
      return Proc.teardown(env, backend, backendSettings)
    })
  })
}
