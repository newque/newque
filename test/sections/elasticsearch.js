var http = require('http')

module.exports = function (backend, backendSettings, raw) {
  var backendSettingsCopy = JSON.parse(JSON.stringify(backendSettings))
  backendSettingsCopy.baseUrls = ['http://127.0.0.1:' + C.remotePort]
  backendSettingsCopy.timeout = 1000
  describe('Elasticsearch-specific ' + backend + (!!raw ? ' raw' : ''), function () {
    this.timeout(C.esTimeout)
    var env
    var server
    before(function (done) {
      server = http.createServer(function (req, res) {
        req.on('error', function (err) {
          console.log('ERROR', err)
          throw err
        })

        var parts = req.url.split('/')
        // console.log(parts, req.method)

        if (req.method === 'POST' && parts.length === 2) {
          res.writeHead(200)
          return res.end()
        } else if (req.method === 'GET' && parts[2] === '_stats' && parts[3] === 'docs') {
          res.writeHead(200)
          return res.end()
        }

      }).listen(C.remotePort, done)
    })
    before(function () {
      this.timeout(C.setupTimeout)

      return Proc.setupEnvironment(backend, backendSettingsCopy, raw)
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
        Fn.call('GET', 8000, '/v1/example/count').then(Fn.shouldFail(500)),
        Fn.call('POST', 8000, '/v1/example', 'somestring', [[C.modeHeader, 'single']]).then(Fn.shouldFail(500))
      ]))
      .then(function (done) {
        server.close(done)
      })
    })

    after(function () {
      return Proc.teardown(env, backend, backendSettingsCopy)
    })
  })
}
