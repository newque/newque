var assert = require('assert')
var fs = require('fs')
var protobuf = require("protocol-buffers")
var specs = protobuf(fs.readFileSync('../protobuf/zmq_obj.proto'))

var zmq = require('zmq')
var addrUpstream = 'tcp://127.0.0.1:8008'
var addrClient = 'tcp://127.0.0.1:8005'
var upstream = zmq.socket('dealer')
upstream.connect(addrUpstream)

var tracker = {}
var timings = []
var msgsPerBatch = 100
var batchesSent = 1000
var batchesReceived = 0
var resolvePromise
var finishedPromise = new Promise(function (resolve, reject) {
  resolvePromise = resolve
})
var str = s => s ? s.toString('utf8') : s

upstream.on('message', function (uid, input, batchID) {
  var args = (arguments.length === 1 ? [arguments[0]] : Array.apply(null, arguments))
  batchesReceived++

  var batch = str(batchID)
  timings.push(Date.now() - tracker[batch])
  delete tracker[batch]

  var messages = []
  for (var i = 3; i < args.length; i++) {
    messages.push(str(args[i]))
  }
  var decoded = specs.Input.decode(input)

  if (decoded.write_input) {
    assert(decoded.write_input.ids.length === (msgsPerBatch + 1))
    assert(messages.length === msgsPerBatch)

    var output = specs.Output.encode({
      errors: [],
      write_output: {
        saved: messages.length
      }
    })
    upstream.send([uid, output])
  }

  if (batchesReceived === batchesSent) {
    resolvePromise()
  }
})

var idCtr = 0
var batchCtr = 0

var client = zmq.socket('dealer')
client.connect(addrClient)
client.on('message', function(uid, input) {
  var messages = Array.prototype.slice.call(arguments, 2).map(str)
  var decoded = specs.Output.decode(input)
  if (decoded.errors.length > 0) {
    console.log('Request errors: ', decoded.errors.map(str))
  }
})

for (var i = 0; i < batchesSent; i++) {
  var frames = new Array()
  frames.push('Some UID')

  // Make IDs
  var ids = new Array()
  ids.push('')
  for (var j = 0; j < msgsPerBatch; j++) {
    ids.push('id' + (idCtr++))
  }

  var input = specs.Input.encode({
    channel: 'example_bench',
    write_input: {
      atomic: false,
      ids: ids
    }
  })
  frames.push(input)
  var batch = batchCtr++
  frames.push(batch)

  // Make messages
  for (var j = 0; j < msgsPerBatch; j++) {
    var msg = new Array()
    for (var k = 0; k < 10; k++) {
      msg.push(Math.round(Math.random() * 999999999))
    }
    frames.push(msg.join(''))
  }

  tracker[batch] = Date.now()
  // console.log(frames)
  client.send(frames)
}

finishedPromise
.then(function () {
  console.log('All received!')
  console.log(Math.round(timings.reduce((a, b) => a + b) / timings.length))

  upstream.removeAllListeners('message')
  upstream.disconnect(addrUpstream)
  client.removeAllListeners('message')
  client.disconnect(addrClient)
})
