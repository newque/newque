var http = require('http')

module.exports = function (backend, backendSettings, raw) {
  describe('Httpproxy-specific ' + backend + (!!raw ? ' raw' : ''), function () {
    var env
    var server
    before(function (done) {
      server = http.createServer(function (req, res) {
        req.on('error', function (err) {
          console.log('ERROR', err)
          throw err
        })

        Fn.assert(req.headers['secret-token'] === 'supersecret')
        var parts = req.url.split('/')
        Fn.assert(parts[0] === '')
        Fn.assert(parts[1] === 'v1')
        if (parts[3] === 'health') {
          return res.end(JSON.stringify({errors:[], code:200}))
        }

      }).listen(C.remotePort, done)
    })
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

    it('Timeouts', function () {
      this.timeout(5000)
      var ctr = 0

      return Promise.delay(200).then(() => Promise.all([
        Fn.call('GET', 8000, '/v1/example/count').then(Fn.shouldFail(400)),
        Fn.call('GET', 8000, '/v1/example', null, [[C.modeHeader, 'one']]).then(Fn.shouldFail(400)),
        Fn.call('POST', 8000, '/v1/example', 'somestring', [[C.modeHeader, 'single']]).then(Fn.shouldFail(400)),
        Fn.call('DELETE', 8000, '/v1/example').then(Fn.shouldFail(400))
      ]))
      .then(function (done) {
        server.close(done)
      })
    })

    after(function () {
      return Proc.teardown(env, backend, backendSettings)
    })
  })
}
