module.exports = function (backend, backendSettings, raw) {
  var delay = backend === 'elasticsearch' ? C.esDelay : 0
  describe('Delete ' + backend + (!!raw ? ' raw' : ''), function () {
    var env
    before(function () {
      this.timeout(C.setupTimeout)
      return Proc.setupEnvironment(backend, backendSettings, raw)
      .then(function (pEnv) {
        env = pEnv
        return Promise.delay(C.spawnDelay)
      })
      .then(function () {
        var buf = `{"a":"abc"}\n{"a":"def"}\n{"a":"ghi"}\n{"a":"jkl"}`
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'multiple']])
        .then(Fn.shouldHaveWritten(4))
        .delay(delay)
      })
    })
    beforeEach(function () {
      Scenarios.clear()
    })

    it('Deletes', function () {
      Scenarios.set('example', 'count', 4)
      return Fn.call('GET', 8000, '/v1/example/count')
      .then(Fn.shouldHaveCounted(4))
      .then(() => Fn.call('DELETE', 8000, '/v1/example'))
      .then(Fn.shouldReturn(200, {code:200, errors:[]}))
      .then(() => Fn.call('GET', 8000, '/v1/example/count'))
      .then(Fn.shouldHaveCounted(0))
    })

    it('Invalid path', function () {
      return Fn.call('DELETE', 8000, '/v1/nothing/')
      .then(Fn.shouldFail(400))
    })

    it('Invalid method', function () {
      return Fn.call('XYZ', 8000, '/v1/example/')
      .then(Fn.shouldFail(400))
    })

    it('Not emptiable', function () {
      return Fn.call('DELETE', 8000, '/v1/secondary')
      .then(Fn.shouldFail(400))
    })

    after(function () {
      return Proc.teardown(env, backend, backendSettings)
    })
  })
}
