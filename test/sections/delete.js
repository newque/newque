module.exports = function (persistence, persistenceSettings, raw) {
  var delay = persistence === 'elasticsearch' ? C.esDelay : 0
  describe('Delete ' + persistence + (!!raw ? ' raw' : ''), function () {
    var processes = []
    before(function () {
      this.timeout(C.setupTimeout)
      return Proc.setupEnvironment(persistence, persistenceSettings, raw)
      .then(function (procs) {
        procs.forEach((p) => processes.push(p))
        return Promise.delay(C.spawnDelay * processes.length)
      })
      .then(function () {
        var buf = `{"a":"abc"}\n{"a":"def"}\n{"a":"ghi"}\n{"a":"jkl"}`
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'multiple']])
        .then(Fn.shouldHaveWritten(4))
        .delay(delay)
      })
    })

    it('Deletes', function () {
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
      return Proc.teardown(processes, persistence, persistenceSettings)
    })
  })
}
