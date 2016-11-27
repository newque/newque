var zmq = require('zmq')
var fs = require('fs')
var protobuf = require("protocol-buffers")
var socket = zmq.socket('dealer')

// The monitor checks for state errors every 500ms and must be restarted on errors
socket.on('monitor_error', function(err) {
  console.log('Error in monitoring: %s, will restart monitoring in 5 seconds', err)
  setTimeout(function() { socket.monitor(500, 0) }, 500)
})

socket.connect('tcp://127.0.0.1:8005')

// Load the proto file
var specs = protobuf(fs.readFileSync('../protobuf/zmq_obj.proto'))
// console.log(specs)
// var obj = specs.Input.decode(new Buffer('CgxkZXJwIGNoYW5uZWxaEQgBEgNpZDQSA2lkNRIDaWQ2', 'base64'))
// console.log(obj)

var str = s => s ? s.toString('utf8') : s
var router = {}
var counter = 0

// NOTE: concat() and slice() are not efficient the way they're used
// throughout this program. This code is for test purposes only.
var sendZMQ = function (frames) {
  var id = counter++

  // TODO: Put a timeout on this promise to make it
  // reject() and clean up its registered handler.
  return new Promise(function (resolve, reject) {
    socket.send([id].concat(frames))
    router[id] = {resolve: resolve, reject: reject}
  })
}

var sendWrite = function (channel, atomic, ids, msgs) {
  var buf = specs.Input.encode({
    channel: channel,
    write: {
      atomic: atomic,
      ids: ids
    }
  })
  return sendZMQ([buf].concat(msgs))
  .then(function (frames) {
    // the 'message' event listener guarantees this array isn't empty
    var buf = frames[0]
    console.log(buf.toString('utf8'))
    var obj = specs.Write.decode(buf)
    console.log(obj)
    console.log(frames[1].toString('utf8'))
    console.log(frames[2])
  })
}

socket.on('message', function() {
  var frames = Array.prototype.slice.call(arguments, 0)
  if (frames.length < 2) {
    return console.log('Invalid messages returned by Newque, please report this bug.')
  }
  var sid = str(frames[0])
  var handler = router[sid]
  delete router[sid]
  if (handler) {
    handler.resolve(frames.slice(1))
  } else {
    return console.log('Our client app crashed, this message was lost', sid, str(msg))
  }
})

sendWrite('example', true, ['id4', 'id5', 'id6'], ['abc', 'def', 'ghi'])

// Make calls
// sendZMQ('Call ONE!!!')
// .then(function (msg) {
//   // do stuff with the response
//   console.log(str(msg))
// })
// .catch(function (err) {
//   // handle errors
//   console.log(err)
// })

