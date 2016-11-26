var zmq = require('zmq')
var socket = zmq.socket('dealer')

// The monitor checks for state errors every 500ms and must be restarted on errors
socket.on('monitor_error', function(err) {
  console.log('Error in monitoring: %s, will restart monitoring in 5 seconds', err)
  setTimeout(function() { socket.monitor(500, 0) }, 500)
})

socket.connect('tcp://127.0.0.1:8000')

var str = s => s ? s.toString('utf8') : s
var router = {}
var counter = 0

var sendZMQ = function (msg) {
  var id = counter++

  // TODO: Put a timeout on this promise to make it
  // reject() and clean up its registered handler
  return new Promise(function (resolve, reject) {
    socket.send([id, msg])
    router[id] = {resolve: resolve, reject: reject}
  })
}

socket.on('message', function(id, msg) {
  var sid = str(id)
  var handler = router[sid]
  delete router[sid]
  if (handler) {
    handler.resolve(msg)
  } else {
    console.log('Our client app crashed, this message was lost', sid, str(msg))
  }
})

// Make calls
sendZMQ('Call ONE!!!')
.then(function (msg) {
  // do stuff with the response
  console.log(str(msg))
})
.catch(function (err) {
  // handle errors
  console.log(err)
})

sendZMQ('Call TWO!!!').then(msg => console.log(str(msg)))
sendZMQ('Call THREE!!!').then(msg => console.log(str(msg)))
sendZMQ('Call FOUR!!!').then(msg => console.log(str(msg)))
sendZMQ('Call FIVE!!!').then(msg => console.log(str(msg)))
sendZMQ('Call SIX!!!').then(msg => console.log(str(msg)))

