exports.modeHeader = 'newque-mode'
exports.idHeader = 'newque-msg-id'
exports.lengthHeader = 'newque-response-length'
exports.lastIdHeader = 'newque-response-last-id'
exports.lastTsHeader = 'newque-response-last-ts'
exports.limitHeader = 'newque-read-max'

exports.spawnDelay = 1000
exports.setupTimeout = 10000

exports.esDelay = 1500 // Due to ES's refresh interval default being 1000ms
exports.esTimeout = 7000 // Test timeouts due to ES being slow

exports.redisDelay = 100

exports.remotePort = 8100
