module.exports = function (id) {
  describe('Pull ' + id, function () {
    var p, env
    before(function () {
      this.timeout(10000)
      return Proc.setupEnvironment(id)
      .then(function (environment) {
        env = environment
        p = Proc.spawnExecutable()
        return Promise.delay(C.spawnDelay)
      })
      .then(function () {
        var buf = 'M abc\nM def\nM ghi\nM jkl'
        return Fn.call('POST', 8000, '/example', buf, [[C.modeHeader, 'multiple']])
        .then(Fn.shouldHaveWritten(4))
      })
      .then(function () {
        var buf = 'XYZ\nABCD\n'
        return Fn.call('POST', 8000, '/secondary', buf, [[C.modeHeader, 'multiple']])
        .then(Fn.shouldHaveWritten(3))
      })
    })

    it('One, with header', function () {
      return Fn.call('GET', 8000, '/example', null, [[C.modeHeader, "one"]])
      .then(Fn.shouldHaveRead(['M abc'], '\n'))
    })

    it('One, without header', function () {
      return Fn.call('GET', 8000, '/example')
      .then(Fn.shouldHaveRead(['M abc'], '\n'))
    })

    it('One, with header, secondary channel', function () {
      return Fn.call('GET', 8000, '/secondary', null, [[C.modeHeader, "one"]])
      .then(Fn.shouldHaveRead(['XYZ'], '\n'))
    })

    it('One, without header, secondary channel', function () {
      return Fn.call('GET', 8000, '/secondary')
      .then(Fn.shouldHaveRead(['XYZ'], '\n'))
    })

    after(function () {
      return Proc.stopExecutable(p)
    })
  })
}
