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
var messages = ['THIS IS A MESSAGE!!!!', 'THIS IS ANOTHER MESSAGE']
var request = specs.Input.encode({
  channel: 'example_pubsub',
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



/****** Pubsub ZMQ Socket for our channel ******/
var sub = zmq.socket('sub')
sub.connect('tcp://127.0.0.1:8006')
sub.subscribe(new Buffer([]))
sub.on('message', function(input, message1, message2) {
  var decoded = specs.Input.decode(input)
  console.log('Received Channel:', str(decoded.channel))
  console.log('Received IDs:', decoded.write_input.ids.map(str))
  console.log(str(message1))
  console.log(str(message2))

  process.exit(0)
})

/****** Send it off! ******/
socket.send([UID, request].concat(messages))
