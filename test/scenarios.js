
var state = {
  queues: {}, // per channel name
  KVs: {} // per channel name
}

var checkName = function (name) {
  if (state.queues[name] == null) {
    state.queues[name] = []
  }
  if (state.KVs[name] == null) {
    state.KVs[name] = {}
  }
}

exports.set = function (name, key, value, times) {
  checkName(name)
  var times = times != null ? times : 1
  for (var i = 0; i < times; i++){
    if (state.KVs[name][key] == null) {
      state.KVs[name][key] = [value]
    } else {
      state.KVs[name][key].push(value)
    }
  }
}

exports.get = function (name, key) {
  checkName(name)
  if (state.KVs[name][key] != null) {
    return state.KVs[name][key].shift()
  }
}

exports.peek = function (name, key) {
  checkName(name)
  if (state.KVs[name][key] != null) {
    return state.KVs[name][key][0]
  }
}

exports.push = function (name, values) {
  checkName(name)
  values.forEach(v => state.queues[name].push(v))
}

exports.pop = function (name) {
  checkName(name)
  var element = state.queues[name].pop()
  Fn.assert(element != null)
  return element
}

exports.take = function (name) {
  checkName(name)
  var element = state.queues[name].shift()
  Fn.assert(element != null)
  return element
}

exports.count = function (name) {
  checkName(name)
  return state.queues[name].reduce(function (acc, arr) {
    return acc + arr.length
  }, 0)
}

exports.clearQueue = function (name) {
  state.queues[name] = []
}

exports.printQueues = function () {
  console.log(state.queues)
}

exports.clear = function () {
  state.queues = {}
  state.KVs = {}
}
