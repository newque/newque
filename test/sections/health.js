module.exports = function (persistence, persistenceSettings, raw) {
  var delay = persistence === 'elasticsearch' ? 1000 : 0
  describe('Health ' + persistence + (!!raw ? ' raw' : ''), function () {
    var processes = []
    before(function () {
      this.timeout(5000)
      return Proc.setupEnvironment(persistence, persistenceSettings, raw)
      .then(function (procs) {
        procs.forEach((p) => processes.push(p))
        return Promise.delay(C.spawnDelay * processes.length)
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
      return Proc.teardown(processes, persistence, persistenceSettings)
    })
  })
}
