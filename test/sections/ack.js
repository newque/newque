module.exports = function (persistence, persistenceSettings, raw) {
  var delay = persistence === 'elasticsearch' ? 1100 : 0
  describe('Ack ' + persistence + (!!raw ? ' raw' : ''), function () {
    var processes = []
    before(function () {
      this.timeout(5000)
      return Proc.setupEnvironment(persistence, persistenceSettings, raw)
      .then(function (procs) {
        procs.forEach((p) => processes.push(p))
        return Promise.delay(C.spawnDelay * processes.length)
      })
    })

    it('Saved', function () {
      var buf = 'AAA\nBBB\nCCC\nDDD'
      return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'multiple']])
      .then(Fn.shouldHaveWritten(4))
      .then(() => Fn.call('GET', 8000, '/v1/example', null, [[C.modeHeader, 'many 4']]))
      .then(Fn.shouldHaveRead(['AAA', 'BBB', 'CCC', 'DDD'], '\n'))
    })

    it('None', function () {
      var buf = 'eee\nfff\nggg\nhhh'
      return Fn.call('POST', 8000, '/v1/noack', buf, [[C.modeHeader, 'multiple']])
      .then(Fn.shouldHaveWrittenAsync())
      .delay(10)
      .then(() => Fn.call('GET', 8000, '/v1/noack', null, [[C.modeHeader, 'many 4']]))
      .then(Fn.shouldHaveRead(['eee', 'fff', 'ggg', 'hhh'], '\n'))
    })

    after(function () {
      return Proc.teardown(processes, persistence, persistenceSettings)
    })
  })
}
