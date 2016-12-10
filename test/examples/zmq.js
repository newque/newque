var zmq = require('zmq')
var fs = require('fs')
var protobuf = require("protocol-buffers")

/****** ZMQ ******/
var socket = zmq.socket('dealer')

// The monitor checks for state errors every 500ms and must be restarted on errors
socket.on('monitor_error', function(err) {
  console.log('Error in monitoring: %s, will restart monitoring in 5 seconds', err)
  setTimeout(function() { socket.monitor(500, 0) }, 500)
})

socket.connect('tcp://127.0.0.1:8005')

/****** SETUP ******/
// Load the proto file
var specs = protobuf(fs.readFileSync('../protobuf/zmq_obj.proto'))

var str = s => s ? s.toString('utf8') : s
var router = {}
// To avoid id collisions when apps crash or restart
var tag = require('crypto').randomBytes(12).toString('base64') + '_'
var counter = 0

socket.on('message', function() {
  var frames = Array.prototype.slice.call(arguments, 0)
  if (frames.length < 2) {
    // There's always at least an ID an Output object
    return console.log('Invalid messages returned by Newque, please report this bug.')
  }
  var sid = str(frames[0])
  var handler = router[sid]
  delete router[sid]
  if (handler) {
    handler.resolve({
      response: specs.Output.decode(frames[1]),
      messages: frames.slice(2)
    })
  } else {
    return console.log('Our client app crashed, this message wasn\'t processed', sid, frames.slice(1))
  }
})

/****** METHODS ******/
// NOTE: concat() and slice() are not efficient the way they're used
// throughout this program. This code is for test purposes only.
var sendZMQ = function (frames) {
  var id = tag + counter++

  // TODO: Put a timeout on this promise to make it
  // reject() and clean up its registered handler.
  return new Promise(function (resolve, reject) {
    router[id] = {resolve: resolve, reject: reject}
    socket.send([id].concat(frames))
  })
}

var sendWrite = function (channel, atomic, ids, msgs) {
  var buf = specs.Input.encode({
    channel: channel,
    write_input: {
      atomic: atomic,
      ids: ids
    }
  })
  return sendZMQ([buf].concat(msgs))
}

var sendRead = function (channel, mode, limit) {
  var buf = specs.Input.encode({
    channel: channel,
    read_input: {
      mode: mode,
      limit: limit
    }
  })
  return sendZMQ([buf])
}

var sendCount = function (channel) {
  var buf = specs.Input.encode({
    channel: channel,
    count_input: {}
  })
  return sendZMQ([buf])
}

var sendDelete = function (channel) {
  var buf = specs.Input.encode({
    channel: channel,
    delete_input: {}
  })
  return sendZMQ([buf])
}

var sendHealth = function (channel, checkAll) {
  var buf = specs.Input.encode({
    channel: channel,
    health_input: {
      global: checkAll
    }
  })
  return sendZMQ([buf])
}


/****** EXAMPLES ******/
var channelName = 'example'

var displayResult = function (result) {
  if (result.response.errors.length > 0) {
    console.log('Errors:', result.response.errors.map(str))
  }
  if (result.messages.length > 0) {
    console.log('DATA:', result.messages.map(str))
  }
  console.log(result)
}

sendWrite(channelName, true, ['id4', 'id5', 'id6'], ['abc', 'def', 'ghi'])
.then(function (result) {
  console.log('Write example:')
  displayResult(result)
  console.log('---------------\n')

  return sendCount(channelName)
})
.then(function (result) {
  console.log('Count example (after writing):')
  displayResult(result)
  console.log('---------------\n')

  return sendRead(channelName, 'many 5')
})
.then(function (result) {
  console.log('Read example')
  displayResult(result)
  console.log('---------------\n')

  return sendDelete(channelName)
})
.then(function (result) {
  console.log('Delete example:')
  displayResult(result)
  console.log('---------------\n')

  return sendCount(channelName)
})
.then(function (result) {
  console.log('Count example (after deleting):')
  displayResult(result)
  console.log('---------------\n')

  return sendHealth(channelName, true)
})
.then(function (result) {
  console.log('Health example:')
  displayResult(result)
  console.log('---------------\n')

  return sendZMQ(['this is obviously totally invalid'])
})
.then(function (result) {
  console.log('Failure example:')
  displayResult(result)
  console.log('---------------\n')
})
.catch(function (err) {
  console.log(err)
  console.log(err.stack)
})
.then(function () {
  process.exit(0)
})


