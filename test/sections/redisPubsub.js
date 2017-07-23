var fs = require('fs')
var protobuf = require("protocol-buffers")
var specs = protobuf(fs.readFileSync('../specs/zmq_api.proto'))
var redis = require('redis')
var client1 = redis.createClient()
var client2 = redis.createClient()

module.exports = function (backend, backendSettings, raw) {
  describe('RedisPubsub' + (!!raw ? ' raw' : ''), function () {
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

    it('Pull', function () {
      return Fn.call('GET', 8000, '/v1/example', null, [[C.modeHeader, 'one']])
      .then(Fn.shouldFail(400))
    })

    it('Count', function () {
      return Fn.call('GET', 8000, '/v1/example/count')
      .then(Fn.shouldFail(400))
    })

    it('Delete', function () {
      Fn.call('DELETE', 8000, '/v1/example')
      .then(Fn.shouldFail(400))
    })

    it('Push to multiple subscribers', function () {
      var originalIds = ['id1', 'id2', 'id3', 'id4']
      var originalIdsStr = originalIds.join(',')
      var buf = `{"a":"abc"}\n{"a":"def"}\n{"a":"ghi"}\n{"a":"jkl"}`

      var receiveOnClient = function (client, broadcast) {
        return new Promise(function (resolve, reject) {
          client.on('error', function (err) {
            return reject(err)
          })
          client.subscribe(broadcast)
          client.on('message_buffer', function (channel, many) {
            var unwrapped = specs.Many.decode(many)
            var decoded = specs.Input.decode(unwrapped.buffers[0])
            var msg1 = unwrapped.buffers[1]
            var msg2 = unwrapped.buffers[2]
            var msg3 = unwrapped.buffers[3]
            var msg4 = unwrapped.buffers[4]

            Fn.assert(decoded.channel.toString('utf8') === 'example')
            Fn.assert(decoded.write_input.atomic !== true)
            var receivedIds = decoded.write_input.ids.map(x => x.toString('utf8'))
            Fn.assert(receivedIds.join(',') === originalIdsStr)
            var splitBuf = buf.split('\n')

            Fn.assert(msg1.toString('utf8') === splitBuf[0])
            Fn.assert(msg2.toString('utf8') === splitBuf[1])
            Fn.assert(msg3.toString('utf8') === splitBuf[2])
            Fn.assert(msg4.toString('utf8') === splitBuf[3])

            client.removeAllListeners('message_buffer')
            client.removeAllListeners('error')
            client.unsubscribe()
            resolve()
          })
        })
      }
      var receive1 = receiveOnClient(client1, backendSettings.broadcast)
      var receive2 = receiveOnClient(client2, backendSettings.broadcast)
      return Fn.call('POST', 8000, '/v1/example', buf, [[C.modeHeader, 'multiple'], [C.idHeader, originalIdsStr]])
      .then(Fn.shouldHaveWritten(4))
      .then(() => receive1)
      .then(() => receive2)
    })

    it('Should split into single flushes', function () {
      var originalIds = ['id1', 'id2', 'id4', 'id8']
      var originalIdsStr = originalIds.join(',')
      var buf = `1\n2\n4\n8`
      var shouldTotal = 1 + 2 + 4 + 8

      var receiveOnClient = function (client, broadcast) {
        var total = 0
        return new Promise(function (resolve, reject) {
          client.on('error', function (err) {
            return reject(err)
          })
          client.subscribe(broadcast)
          client.on('message_buffer', function (channel, many) {
            var unwrapped = specs.Many.decode(many)
            var decoded = specs.Input.decode(unwrapped.buffers[0])
            var msg = unwrapped.buffers[1]
            Fn.assert(decoded.channel.toString('utf8') === 'singlebatches')
            Fn.assert(decoded.write_input.atomic !== true)

            var receivedIds = decoded.write_input.ids.map(x => x.toString('utf8'))
            var receivedMsg = msg.toString('utf8')
            Fn.assert(receivedIds.length === 1)
            Fn.assert(receivedIds[0] === 'id' + receivedMsg)
            var splitBuf = buf.split('\n')

            total += parseInt(receivedMsg, 10)
            if (total === shouldTotal) {
              client.removeAllListeners('message_buffer')
              client.removeAllListeners('error')
              client.unsubscribe()
              resolve()
            }
          })
        })
      }
      var receive1 = receiveOnClient(client1, backendSettings.broadcast)
      var receive2 = receiveOnClient(client2, backendSettings.broadcast)
      return Fn.call('POST', 8000, '/v1/singlebatches', buf, [[C.modeHeader, 'multiple'], [C.idHeader, originalIdsStr]])
      .then(Fn.shouldHaveWritten(4))
      .then(() => receive1)
      .then(() => receive2)
    })

    after(function () {
      return Proc.teardown(env, backend, backendSettings)
    })
  })
}
