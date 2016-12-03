module.exports = function (backend, backendSettings, raw) {
  var delay = backend === 'elasticsearch' ? C.esDelay : 0
  describe('Health ' + backend + (!!raw ? ' raw' : ''), function () {
    var processes = []
    before(function () {
      this.timeout(C.setupTimeout)
      return Proc.setupEnvironment(backend, backendSettings, raw)
      .then(function (env) {
        env.processes.forEach((p) => processes.push(p))
        return Promise.delay(C.spawnDelay)
      })
    })

    var makeItFail = {

    }

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
      return Proc.teardown(processes, backend, backendSettings)
    })
  })
}
