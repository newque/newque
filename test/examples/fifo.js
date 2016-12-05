var util = require('util')
var zmq = require('zmq')
var fs = require('fs')
var protobuf = require("protocol-buffers")
var specs = protobuf(fs.readFileSync('../protobuf/zmq_obj.proto'))

/****** Main ZMQ Socket ******/
var socket = zmq.socket('dealer')

// The monitor checks for state errors every 500ms and must be restarted on errors
socket.on('monitor_error', function(err) {
  console.log('Error in monitoring: %s, will restart monitoring in 5 seconds', err)
  setTimeout(function() { socket.monitor(500, 0) }, 500)
})

socket.connect('tcp://127.0.0.1:8005')

var str = s => s ? s.toString('utf8') : s

var UID = 'this is our random UID'
var messages = ['Something!!', 'Some other thing!!!']
var request = specs.Input.encode({
  channel: 'example_fifo',
  write_input: {
    atomic: false,
    ids: [] // Optional
  }
})

socket.on('message', function(uid, output) {
  var decoded = specs.Output.decode(output)
  console.log('Ack:', str(uid), decoded)
  console.log(decoded.errors.map(str))
})



/****** Fifo ZMQ Socket for our channel ******/
var fifo = zmq.socket('dealer')
fifo.connect('tcp://127.0.0.1:8007')
fifo.on('message', function(uid, input) {
  var messages = Array.prototype.slice.call(arguments, 2).map(str)
  var decoded = specs.Input.decode(input)
  console.log('Received (' + str(decoded.channel) + '):', messages,
    ', IDs:', JSON.stringify(decoded.write_input.ids.map(str)), '\n'
  )

  var encoded = specs.Output.encode({
    errors: [],
    write_output: {
      saved: 2
    }
  })
  fifo.send([uid, encoded])

  process.exit(0)
})


/****** Send it off! ******/
socket.send([UID, request].concat(messages))
