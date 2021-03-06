module.exports = function (backend, backendSettings, raw) {
  describe('Push ' + backend + (!!raw ? ' raw' : ''), function () {
    if (backend === 'elasticsearch') {
      var delay = C.esDelay
      this.timeout(C.esTimeout)
    } else {
      var delay = 0
    }
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

    describe('Single', function () {
      if (backend !== 'elasticsearch') { // Because they test 'Single'
        it('No header', function () {
          this.timeout(5000)
          var buf = 'abc\ndef'
          return Fn.call('POST', 8000, '/v1/example', buf)
          .then(Fn.shouldHaveWritten(1))
        })

        it('No data', function () {
          var buf = ''
          return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'single']])
          .then(Fn.shouldHaveWritten(1))
        })

        it('With separator', function () {
          var buf = '{"somefield":"abc"}\n{"somefield":"ndef"}'
          return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'single']])
          .then(Fn.shouldHaveWritten(1))
        })
      }

      it('With header', function () {
        var buf = '{"qwerty":"abcdef"}'
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'single']])
        .then(Fn.shouldHaveWritten(1))
      })

      it('With bad header', function () {
        var buf = '{"somefield":"abcdef"}'
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'invalid header']])
        .then(Fn.shouldFail(400))
      })
    })

    describe('Multiple', function () {
      it('Without separator', function () {
        var buf = '{"somefield":"abcdef"}'
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'multiple']])
        .then(Fn.shouldHaveWritten(1))
      })

      it('With separator', function () {
        var buf = '{"xyz":"M abc"}\n{"xyz":"M def"}\n{"xyz":"M ghi"}\n{"xyz":"M jkl"}'
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'multiple']])
        .then(Fn.shouldHaveWritten(4))
      })

      it('With separator, secondary channel', function () {
        var buf = '{"xyz":"M abc"}--{"xyz":"M def"}--{"xyz":"M ghi"}--{"xyz":"M jkl"}'
        return Fn.call('POST', 8000, '/v1/secondary', buf, [[C.modeHeader, 'multiple']])
        .then(Fn.shouldHaveWritten(4))
      })

      if (backend !== 'elasticsearch') {
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
      }
    })

    if (!raw) {
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
    }

    describe('Custom IDs', function () {
    // Set up an initial ID to track...
      var lastID = 'initial'
      before(function () {
        var buf = '{"abc":"bzzz"}'
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'single'], [C.idHeader, lastID]])
        .then(Fn.shouldHaveWritten(1))
      })

      if (backend !== 'elasticsearch') {
        it('Without separator, single mode', function () {
          var buf = 'A abc\nA def\nA ghi\nA jkl'
          Scenarios.set('example', 'last_id', lastID)
          Scenarios.set('example', 'last_timens', 999)

          return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'single'], [C.idHeader, 'id1']])
          .then(Fn.shouldHaveWritten(1))
          // Check that only one was added after the previous lastID, then update the lastID
          .then(() => Fn.call('GET', 8000, '/v1/example', null, [[C.modeHeader, 'after_id ' + lastID]]))
          .then(Fn.shouldHaveRead([buf], '\n'))
          .then(result => lastID = result.res.headers[C.lastIdHeader])
        })

        it('With separator, single mode', function () {
          var buf = 'B abc\nB def\nB ghi\nB jkl'
          Scenarios.set('example', 'last_id', lastID)
          Scenarios.set('example', 'last_timens', 999)

          return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'single'], [C.idHeader, 'id1,id2']])
          .then(Fn.shouldHaveWritten(1))
          // Check that only one was added after the previous lastID, then update the lastID
          .then(() => Fn.call('GET', 8000, '/v1/example', null, [[C.modeHeader, 'after_id ' + lastID]]))
          .then(Fn.shouldHaveRead([buf], '\n'))
          .then(result => lastID = result.res.headers[C.lastIdHeader])
        })

        it('Without separator', function () {
          var buf = 'abcdef'
          Scenarios.set('example', 'last_id', lastID)
          Scenarios.set('example', 'last_timens', 999)

          return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'single'], [C.idHeader, 'id10,id11,id12,id13']])
          .then(Fn.shouldHaveWritten(1))
          // Check that only one was added after the previous lastID, then update the lastID
          .then(() => Fn.call('GET', 8000, '/v1/example', null, [[C.modeHeader, 'after_id ' + lastID]]))
          .then(Fn.shouldHaveRead([buf], '\n'))
          .then(result => lastID = result.res.headers[C.lastIdHeader])
        })

        it('With separator', function () {
          var buf = 'C abc\nC def\nC ghi\nC jkl'
          Scenarios.set('example', 'last_id', lastID)
          Scenarios.set('example', 'last_timens', 999)

          return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'multiple'], [C.idHeader, 'id10,id11,id12,id13']])
          .then(Fn.shouldHaveWritten(4))
          // Check that 4 were added after the previous lastID, then update the lastID
          .then(() => Fn.call('GET', 8000, '/v1/example', null, [[C.modeHeader, 'after_id ' + lastID]]))
          .then(Fn.shouldHaveRead(buf.split('\n'), '\n'))
          .then(result => lastID = result.res.headers[C.lastIdHeader])
        })
      }

      it('With separator, non-matching lengths 1', function () {
        var buf = 'D abc\nD def\nD ghi\nD jkl'
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'multiple'], [C.idHeader, 'id20,id21,id22']])
        .then(Fn.shouldFail(400))
      })

      it('With separator, non-matching lengths 2', function () {
        var buf = 'E abc\nE def\nE ghi'
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'multiple'], [C.idHeader, 'id30,id31,id32,id33']])
        .then(Fn.shouldFail(400))
      })

      it('With separator, empty IDs 1', function () {
        var buf = 'F abc\nF def\nF ghi'
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'multiple'], [C.idHeader, 'id40,id41,id42,']])
        .then(Fn.shouldFail(400))
      })

      it('With separator, empty IDs 2', function () {
        var buf = 'G abc\nG def\nG ghi'
        return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'multiple'], [C.idHeader, 'id50,id51,,id52,id53']])
        .then(Fn.shouldFail(400))
      })

      if (!raw && backend !== 'elasticsearch') {
        it('With separator, atomic', function () {
          var buf = 'H abc\nH def\nH ghi'
          Scenarios.set('example', 'last_id', lastID)
          Scenarios.set('example', 'last_timens', 999)

          return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'atomic'], [C.idHeader, 'id60,id61,id62,']])
          .then(Fn.shouldHaveWritten(1))
          // Check that 3 were added after the previous lastID, then update the lastID
          .then(() => Fn.call('GET', 8000, '/v1/example', null, [[C.modeHeader, 'after_id ' + lastID]]))
          .then(Fn.shouldHaveRead(buf.split('\n'), '\n'))
          .then(result => lastID = result.res.headers[C.lastIdHeader])
        })
      }

      if (backend !== 'elasticsearch' && backend !== 'fifo') {
        it('With separator, skip existing', function () {
          var buf = 'I abc\nI def\nI ghi'
          return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'multiple'], [C.idHeader, 'id70,id70,id1']])
          .then(Fn.shouldHaveWritten(1))
          // Check that 3 were added after the previous lastID, then update the lastID
          .then(() => Fn.call('GET', 8000, '/v1/example', null, [[C.modeHeader, 'after_id ' + lastID]]))
          .then(Fn.shouldHaveRead(['I abc'], '\n'))
          .then(result => Fn.assert(result.res.headers[C.lastIdHeader] === 'id70'))
        })
      }
    })

    describe('Forward to channels', function () {
      it('Should also write to sinks (2 sinks, ack)', function () {
        this.timeout(3500)
        var buf = '{"somefield":"Forwarding 1 abc"}\n{"somefield":"Forwarding 1 def"}\n{"somefield":"Forwarding 1 ghi"}\n{"somefield":"Forwarding 1 jkl"}'
        return Fn.call('POST', 8000, '/v1/forwardingAck', buf, [[C.modeHeader, 'multiple']])
        .then(Fn.shouldHaveWritten(4))
        .delay(delay)
        .then(() => Fn.call('GET', 8000, '/v1/sink1/count'))
        .then(Fn.shouldHaveCounted(4))
        .delay(delay)
        .then(() => Fn.call('GET', 8000, '/v1/sink2/count'))
        .then(Fn.shouldHaveCounted(4))
      })

      it('Should also write to sinks (1 sink, no ack)', function () {
        this.timeout(3500)
        var buf = '{"somefield":"Forwarding 2 abc"}\n{"somefield":"Forwarding 2 def"}\n{"somefield":"Forwarding 2 ghi"}\n{"somefield":"Forwarding 2 jkl"}'
        Scenarios.set('sink1', 'count', 8)
        Scenarios.set('sink2', 'count', 4)

        return Fn.call('POST', 8000, '/v1/forwardingNoAck', buf, [[C.modeHeader, 'multiple']])
        .delay(25)
        .then(Fn.shouldHaveWrittenAsync())
        .delay(delay)
        .then(() => Fn.call('GET', 8000, '/v1/sink1/count'))
        .then(Fn.shouldHaveCounted(8))
        .delay(delay)
        .then(() => Fn.call('GET', 8000, '/v1/sink2/count'))
        .then(Fn.shouldHaveCounted(4))
      })
    })

    describe('Scripting', function () {
      if (backend !== 'elasticsearch') { // Because the scripts don't return JSON
        it('Mapping', function () {
          var buf = 'abcdef2'
          Scenarios.set('scripting', 'last_id', 'added by an external script')
          Scenarios.set('scripting', 'last_timens', 999)
          return Fn.call('POST', 8000, '/v1/scripting', buf, [[C.modeHeader, 'single']])
          .then(Fn.shouldHaveWritten(3))
          .then(() => Fn.call('GET', 8000, '/v1/scripting', null, [[C.modeHeader, 'many 3']]))
          .then(Fn.shouldHaveRead(['ABCDEF2', 'added msg 2', 'added by an external script'], '\n'))
        })
      }
      it('Runtime errors', function () {
        var buf = 'abcdef'
        return Fn.call('POST', 8000, '/v1/scripting_invalid', buf, [[C.modeHeader, 'single']])
        .then(Fn.shouldFail(400))
      })
    })

    describe('JSON Schema Validation', function () {
      it('Accept valid objects', function () {
        var buf = '{"abc":{"def":764}}\n{"abc":{"def": 0}}'
        return Fn.call('POST', 8000, '/v1/json_validation', buf, [[C.modeHeader, 'multiple']])
        .then(Fn.shouldHaveWritten(2))
      })

      it('Reject incorrectly-formatted JSON', function () {
        var buf = '{"abc":{def":764}}\n{"abc":{"def": }}'
        return Fn.call('POST', 8000, '/v1/json_validation', buf, [[C.modeHeader, 'multiple']])
        .then(Fn.shouldFail(400))
      })

      it('Reject binary non-JSON data', function () {
        var buf = '{"abc":"def\u9876":{5}}'
        return Fn.call('POST', 8000, '/v1/json_validation', buf, [[C.modeHeader, 'multiple']])
        .then(Fn.shouldFail(400))
      })

      it('Reject invalid JSON object (incorrect type)', function () {
        var buf = '{"abc":{"def":9.5}}'
        return Fn.call('POST', 8000, '/v1/json_validation', buf, [[C.modeHeader, 'multiple']])
        .then(Fn.shouldFail(400))
      })

      it('Reject invalid JSON object (extra key)', function () {
        var buf = '{"abc": {"def":9, "ghi": 10}}'
        return Fn.call('POST', 8000, '/v1/json_validation', buf, [[C.modeHeader, 'multiple']])
        .then(Fn.shouldFail(400))
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
        .then(Fn.shouldFail(400))
      })
    })

    describe('Read only', function () {
      it('Should error when trying to write', function () {
        var buf = 'qwerty'
        return Fn.call('POST', 8000, '/v1/readonly', buf, [[C.modeHeader, 'single']])
        .then(Fn.shouldFail(400))
      })
    })

    describe('Write only', function () {
      it('Should push', function () {
        var buf = '{"xyz":"qwerty"}'
        return Fn.call('POST', 8000, '/v1/writeonly', buf, [[C.modeHeader, 'single']])
        .then(Fn.shouldHaveWritten(1))
      })
    })

    describe('JSON', function () {
      it('Should push multiple (ignores header)', function () {
        var buf = Fn.makeJsonBuffer(['{"xyz":"zxc"}', '{"xyz":"vbn"}'])
        return Fn.call('POST', 8000, '/v1/json', buf, [[C.modeHeader, 'single']])
        .then(Fn.shouldHaveWritten(2))
      })

      if (!raw) {
        it('Should push atomic (ignores header)', function () {
          var buf = Fn.makeJsonBuffer(['{"xyz":"asd"}', '{"xyz":"fgh"}'], null, true)
          return Fn.call('POST', 8000, '/v1/json', buf, [[C.modeHeader, 'single']])
          .then(Fn.shouldHaveWritten(1))
        })
      }

      it('Should push multiple (with IDs)', function () {
        var buf = Fn.makeJsonBuffer(['{"xyz":"qwe"}', '{"xyz":"rty"}'], ['idA', 'idB'])
        return Fn.call('POST', 8000, '/v1/json', buf)
        .then(Fn.shouldHaveWritten(2))
        .then(() => Fn.call('POST', 8000, '/v1/json', buf))
        .then(Fn.shouldHaveWritten(0))
      })

      it('Should push multiple (incorrect IDs)', function () {
        var buf = Fn.makeJsonBuffer(['{"xyz":"qwe"}', '{"xyz":"rty"}'], ['idB'])
        return Fn.call('POST', 8000, '/v1/json', buf)
        .then(Fn.shouldFail(400))
      })

      it('Invalid JSON', function () {
        var buf = '{"messages":]}'
        return Fn.call('POST', 8000, '/v1/json', buf)
        .then(Fn.shouldFail(400))
      })

      it('Invalid format', function () {
        var buf = '{"message":[]}'
        return Fn.call('POST', 8000, '/v1/json', buf)
        .then(Fn.shouldFail(400))
      })

    })

    describe('Batching', function () {
      it('Should buffer for +/- 100 ms', function () {
        var buf1 = Fn.makeJsonBuffer(['{"xyz":"asd"}'], null, false)
        var buf2 = Fn.makeJsonBuffer(['{"xyz":"fgh"}'], null, false)
        var t0 = Date.now()

        return Fn.call('GET', 8000, '/v1/batching/count')
        .then(Fn.shouldHaveCounted(0))
        .then(function () {
          var call1 = Fn.call('POST', 8000, '/v1/batching', buf1)
          var call2 = Fn.call('POST', 8000, '/v1/batching', buf2)

          return call1
          .then(Fn.shouldHaveWritten(1))
          .then(() => call2)
          .then(Fn.shouldHaveWritten(1))
        })
      })

      it('Should flush when full', function () {
        var buf1 = Fn.makeJsonBuffer(['{"xyz":"asd1"}', '{"xyz":"asd2"}', '{"xyz":"asd3"}', '{"xyz":"asd4"}', '{"xyz":"asd5"}'], null, false)
        var buf2 = Fn.makeJsonBuffer(['{"xyz":"fgh"}'], null, false)
        var t0 = Date.now()
        var t1
        Scenarios.set('batching', 'count', 8)
        // This call should be instant, because it fills up the queue
        return Fn.call('POST', 8000, '/v1/batching', buf1)
        .then(Fn.shouldHaveWritten(5))
        .then(function () {
          var took = Date.now() - t0
          // console.log(took)
          Fn.assert(took < 100)

          t1 = Date.now()
          return Fn.call('POST', 8000, '/v1/batching', buf2)
        })
        .then(Fn.shouldHaveWritten(1))
        .delay(delay)
        .then(() => Fn.call('GET', 8000, '/v1/batching/count'))
        .then(Fn.shouldHaveCounted(8))
        .then(function () {
          var took = Date.now() - t1
          // console.log(took)
        })
      })

      if (!raw) {
        it('Should work with atomics', function () {
            var buf1 = Fn.makeJsonBuffer(['aaa', 'bbb'], null, false)
            var buf2 = Fn.makeJsonBuffer(['ccc', 'ddd'], null, true)
            Scenarios.set('batching', 'count', 8)
            Scenarios.set('batching', 'count', 11)

            return Fn.call('GET', 8000, '/v1/batching/count')
            .then(Fn.shouldHaveCounted(8))
            .then(function () {
              var call1 = Fn.call('POST', 8000, '/v1/batching', buf1)
              var call2 = Fn.call('POST', 8000, '/v1/batching', buf2)

              return call1
              .then(Fn.shouldHaveWritten(2))
              .then(() => call2)
              .then(Fn.shouldHaveWritten(1))
              .then(() => Fn.call('GET', 8000, '/v1/batching/count'))
              .then(Fn.shouldHaveCounted(11))
            })
          })
        }
    })

    after(function () {
      this.timeout(C.esTimeout)
      return Proc.teardown(env, backend, backendSettings)
    })
  })
}
