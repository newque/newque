module.exports = function (backend, backendSettings, raw) {
  describe('Health ' + backend + (!!raw ? ' raw' : ''), function () {
    var env
    if (backend === 'elasticsearch') {
      var delay = C.esDelay
      this.timeout(C.esTimeout)
    } else {
      var delay = 0
    }
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

    it('Global', function () {
      return Fn.call('GET', 8000, '/v1/health')
      .then(Fn.shouldReturn(200, {code:200, errors:[]}))
    })

    it('Channel', function () {
      return Fn.call('GET', 8000, '/v1/example/health')
      .then(Fn.shouldReturn(200, {code:200, errors:[]}))
    })

    it('Routing', function () {
      return Fn.call('POST', 8000, '/v1/health')
      .then(Fn.shouldFail(405))
    })

    after(function () {
      this.timeout(C.esTimeout)
      return Proc.teardown(env, backend, backendSettings)
    })
  })
}
