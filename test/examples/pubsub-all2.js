var zmq = require('zmq')
var fs = require('fs')
var protobuf = require("protocol-buffers")

/****** ZMQ ******/
var socket = zmq.socket('pull')

// The monitor checks for state errors every 500ms and must be restarted on errors
socket.on('monitor_error', function(err) {
  console.log('Error in monitoring: %s, will restart monitoring in 5 seconds', err)
  setTimeout(function() { socket.monitor(500, 0) }, 500)
})

socket.connect('tcp://127.0.0.1:8008')

/****** SETUP ******/
// Load the proto file
var specs = protobuf(fs.readFileSync('../protobuf/zmq_obj.proto'))

var str = s => s ? s.toString('utf8') : s

socket.on('message', function(arg1, arg2, arg3) {
  console.log(str(arg1))
  console.log(str(arg2))
  console.log(str(arg3))
})
