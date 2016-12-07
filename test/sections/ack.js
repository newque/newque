module.exports = function (backend, backendSettings, raw) {
  describe('Ack ' + backend + (!!raw ? ' raw' : ''), function () {
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

    it('Saved', function () {
      Scenarios.push('example', [['AAA', 'BBB', 'CCC', 'DDD']])
      Scenarios.set('example', 'last_id', 'something')
      Scenarios.set('example', 'last_timens', 999)
      var buf = 'AAA\nBBB\nCCC\nDDD'
      return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'multiple']])
      .then(Fn.shouldHaveWritten(4))
      .then(() => Fn.call('GET', 8000, '/v1/example', null, [[C.modeHeader, 'many 4']]))
      .then(Fn.shouldHaveRead(['AAA', 'BBB', 'CCC', 'DDD'], '\n'))
    })

    it('None', function () {
      Scenarios.push('noack', [['eee', 'fff', 'ggg', 'hhh']])
      Scenarios.set('noack', 'last_id', 'something')
      Scenarios.set('noack', 'last_timens', 999)
      var buf = 'eee\nfff\nggg\nhhh'
      return Fn.call('POST', 8000, '/v1/noack', buf, [[C.modeHeader, 'multiple']])
      .then(Fn.shouldHaveWrittenAsync())
      .delay(10)
      .then(() => Fn.call('GET', 8000, '/v1/noack', null, [[C.modeHeader, 'many 4']]))
      .then(Fn.shouldHaveRead(['eee', 'fff', 'ggg', 'hhh'], '\n'))
    })

    after(function () {
      return Proc.teardown(env, backend, backendSettings)
    })
  })
}
