module.exports = function (backend, backendSettings, raw) {
  var delay = backend === 'elasticsearch' ? C.esDelay : 0
  describe('Count ' + backend + (!!raw ? ' raw' : ''), function () {
    var processes = []
    before(function () {
      this.timeout(C.setupTimeout)
      return Proc.setupEnvironment(backend, backendSettings, raw)
      .then(function (procs) {
        procs.forEach((p) => processes.push(p))
        return Promise.delay(C.spawnDelay)
      })
      .then(function () {
        var buf = `{"a":"abc"}\n{"a":"def"}\n{"a":"ghi"}\n{"a":"jkl"}`
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'multiple']])
        .then(Fn.shouldHaveWritten(4))
        .delay(delay)
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
      it('Should count', function () {
        return Fn.call('GET', 8000, '/v1/writeonly/count')
        .then(Fn.shouldHaveCounted(0))
      })
    })

    after(function () {
      return Proc.teardown(processes, backend, backendSettings)
    })
  })
}
