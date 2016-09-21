module.exports = function (id) {
  describe('Push ' + id, function () {
    var p, env
    before(function () {
      return Proc.setupEnvironment(id)
      .then(function (environment) {
        env = environment
        p = Proc.spawnExecutable()
        return Promise.delay(C.spawnDelay)
      })
    })

    describe('Single', function () {
      it('No header', function () {
        var buf = 'abcdef'
        return Fn.call('POST', 8000, '/v1/example', buf)
        .then(Fn.shouldFail(400))
      })

      it('No data', function () {
        var buf = ''
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'single']])
        .then(Fn.shouldHaveWritten(1))
      })

      it('With header', function () {
        var buf = 'abcdef'
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'single']])
        .then(Fn.shouldHaveWritten(1))
      })

      it('With separator', function () {
        var buf = 'abc\ndef'
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'single']])
        .then(Fn.shouldHaveWritten(1))
      })

      it('With bad header', function () {
        var buf = 'abcdef'
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'invalid header']])
        .then(Fn.shouldFail(400))
      })
    })

    describe('Multiple', function () {
      it('Without separator', function () {
        var buf = 'abcdef'
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'multiple']])
        .then(Fn.shouldHaveWritten(1))
      })

      it('With separator', function () {
        var buf = 'M abc\nM def\nM ghi\nM jkl'
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'multiple']])
        .then(Fn.shouldHaveWritten(4))
      })

      it('With separator, secondary channel', function () {
        var buf = 'M abc--M def--M ghi--M jkl'
        return Fn.call('POST', 8000, '/v1/secondary', buf, [[C.modeHeader, 'multiple']])
        .then(Fn.shouldHaveWritten(4))
      })

      it('No data', function () {
        var buf = ''
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'multiple']])
        .then(Fn.shouldHaveWritten(1))
      })

      it('Empty messages', function () {
        var buf = '\n\na\n'
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'multiple']])
        .then(Fn.shouldHaveWritten(4))
      })
    })

    describe('Atomic', function () {
      it('Without separator', function () {
        var buf = 'abcdefghijkl'
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'atomic']])
        .then(Fn.shouldHaveWritten(1))
      })

      it('With separator', function () {
        var buf = 'A abc\nA def\nA ghi\nA jkl'
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'atomic']])
        .then(Fn.shouldHaveWritten(1))
      })

      it('Empty messages', function () {
        var buf = '\n\nz\n'
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'atomic']])
        .then(Fn.shouldHaveWritten(1))
      })
    })

    describe('Custom IDs', function () {
      it('Without separator, single mode', function () {
        var buf = 'A abc\nA def\nA ghi\nA jkl'
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'single'], [C.idHeader, 'id1']])
        .then(Fn.shouldHaveWritten(1))
      })

      it('With separator, single mode', function () {
        var buf = 'A abc\nA def\nA ghi\nA jkl'
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'single'], [C.idHeader, 'id1,id2']])
        .then(Fn.shouldHaveWritten(1))
      })

      it('Without separator', function () {
        var buf = 'abcdef'
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'single'], [C.idHeader, 'id10,id11,id12,id13']])
        .then(Fn.shouldHaveWritten(1))
      })

      it('With separator', function () {
        var buf = 'A abc\nA def\nA ghi\nA jkl'
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'multiple'], [C.idHeader, 'id10,id11,id12,id13']])
        .then(Fn.shouldHaveWritten(4))
      })

      it('With separator, non-matching lengths 1', function () {
        var buf = 'A abc\nA def\nA ghi\nA jkl'
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'multiple'], [C.idHeader, 'id20,id21,id22']])
        .then(Fn.shouldFail(400))
      })

      it('With separator, non-matching lengths 2', function () {
        var buf = 'A abc\nA def\nA ghi'
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'multiple'], [C.idHeader, 'id30,id31,id32,id33']])
        .then(Fn.shouldFail(400))
      })

      it('With separator, empty IDs 1', function () {
        var buf = 'A abc\nA def\nA ghi'
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'multiple'], [C.idHeader, 'id40,id41,id42,']])
        .then(Fn.shouldFail(400))
      })

      it('With separator, empty IDs 2', function () {
        var buf = 'A abc\nA def\nA ghi'
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'multiple'], [C.idHeader, 'id50,id51,,id52,id53']])
        .then(Fn.shouldFail(400))
      })

      it('With separator, atomic', function () {
        var buf = 'A abc\nA def\nA ghi'
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'atomic'], [C.idHeader, 'id60,id61,id62,']])
        .then(Fn.shouldHaveWritten(1))
      })

      it('With separator, skip existing', function () {
        var buf = 'A abc\nA def\nA ghi'
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'multiple'], [C.idHeader, 'id70,id70,id1']])
        .then(Fn.shouldHaveWritten(1))
      })
    })

    describe('Routing', function () {
      it('Invalid path, empty channel', function () {
        var buf = ''
        return Fn.call('POST', 8000, '/v1/', buf, [[C.modeHeader, 'single']])
        .then(Fn.shouldFail(400))
      })

      it('Invalid path, invalid channel', function () {
        var buf = ''
        return Fn.call('POST', 8000, '/v1/nothing', buf, [[C.modeHeader, 'single']])
        .then(Fn.shouldFail(400))
      })

      it('Invalid method', function () {
        var buf = ''
        return Fn.call('XYZ', 8000, '/v1/example', buf, [[C.modeHeader, 'single']])
        .then(Fn.shouldFail(405))
      })
    })

    after(function () {
      return Proc.stopExecutable(p)
    })
  })
}
