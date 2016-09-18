describe('Pull', function () {
  var p, env
  before(function () {
    this.timeout(10000)
    return Proc.setupEnvironment(1)
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
  })

  it('One, with header', function () {
    return Fn.call('GET', 8000, '/example', null, [[C.modeHeader, "one"]])
    .then(Fn.shouldHaveRead(['M abc'], '\n'))
  })

  it('One, without header', function () {
    return Fn.call('GET', 8000, '/example')
    .then(Fn.shouldHaveRead(['M abc'], '\n'))
  })

  after(function () {
    return Proc.stopExecutable(p)
  })
})
