module.exports = function (backend, backendSettings, raw) {
  describe('Admin ' + backend + (!!raw ? ' raw' : ''), function () {
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

    var nbChannels

    it('GET /listeners', function () {
      return Fn.call('GET', 8001, '/listeners')
      .then(function (result) {
        Fn.assert(result.res.statusCode === 200)
        Fn.assert(result.body.code === 200)
        Fn.assert(Object.keys(result.body.listeners).length === 2)
        Fn.assert(result.body.listeners.http8000.protocol === 'http')
        Fn.assert(result.body.listeners.http8000.port === 8000)
        Fn.assert(result.body.listeners.http8000.channels.length > 10)
        Fn.assert(result.body.listeners.zmq8005.protocol === 'zmq')
        Fn.assert(result.body.listeners.zmq8005.port === 8005)
        Fn.assert(result.body.listeners.zmq8005.channels.length > 10)

        nbChannels = Math.max(
          result.body.listeners.http8000.channels.length,
          result.body.listeners.zmq8005.channels.length
        )
      })
    })

    it('GET /channels (all)', function () {
      return Fn.call('GET', 8001, '/channels')
      .then(function (result) {
        Fn.assert(result.res.statusCode === 200)
        Fn.assert(result.body.code === 200)
        Fn.assert(Object.keys(result.body.channels.example).length > 5)

        Fn.assert(Object.keys(result.body.channels).length === nbChannels)

      })
    })

    it('GET /channels (one)', function () {
      return Fn.call('GET', 8001, '/channels/secondary')
      .then(function (result) {
        Fn.assert(result.res.statusCode === 200)
        Fn.assert(result.body.code === 200)
        Fn.assert(Object.keys(result.body.channels.secondary).length > 5)

        Fn.assert(Object.keys(result.body.channels).length === 1)
      })
    })

    it('GET /channels (invalid)', function () {
      return Fn.call('GET', 8001, '/channels/thisdoesntexist')
      .then(function (result) {
        Fn.assert(result.res.statusCode === 500)
        Fn.assert(result.body.code === 500)
        Fn.assert(result.body.errors.length > 0)
        Fn.assert(Object.keys(result.body).length === 2)
      })
    })

    it('Invalid path', function () {
      return Fn.call('GET', 8001, '/invalid')
      .then(Fn.shouldFail(404))
    })

    it('Invalid method', function () {
      return Fn.call('XYZ', 8001, '/listeners')
      .then(Fn.shouldFail(404))
    })

    after(function () {
      this.timeout(C.esTimeout)
      return Proc.teardown(env, backend, backendSettings)
    })
  })
}
