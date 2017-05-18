var fs = require('fs')
var protobuf = require("protocol-buffers")
var specs = protobuf(fs.readFileSync('../specs/zmq_api.proto'))
var zmq = require('zmq')
var socket = zmq.socket('dealer')

module.exports = function (backend, backendSettings, raw) {
  describe('Fifo-specific ' + backend + (!!raw ? ' raw' : ''), function () {
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

    it('Timeouts', function () {
      var ctr = 0
      var addr = 'tcp://127.0.0.1:' + env.fifoPorts.example
      socket.connect(addr)
      socket.on('message', function (uid, input) {
        var decoded = specs.Input.decode(input)
        // console.log(decoded.channel.toString('utf8'), decoded)
        Fn.assert(decoded.channel.toString('utf8') === 'example')
        ctr++
      })

      return Promise.delay(200).then(() => Promise.all([
        Fn.call('GET', 8000, '/v1/example/count').then(Fn.shouldFail(500)),
        Fn.call('GET', 8000, '/v1/example', null, [[C.modeHeader, 'one']]).then(Fn.shouldFail(500)),
        Fn.call('POST', 8000, '/v1/example', 'somestring', [[C.modeHeader, 'single']]).then(Fn.shouldFail(500)),
        Fn.call('DELETE', 8000, '/v1/example').then(Fn.shouldFail(500)),
      ]))
      .then(function () {
        Fn.assert(ctr === 5)
        socket.removeAllListeners('message')
        socket.disconnect(addr)
      })
    })

    after(function () {
      return Proc.teardown(env, backend, backendSettings)
    })
  })
}
