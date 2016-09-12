'use strict'

global.Promise = require('bluebird')
var Fn = require('./fn')
var assert = require('assert')
var request = require('superagent')

var modeHeader = 'newque-mode'
var shouldHaveWritten = function (count) {
  return function (result) {
    return new Promise(function (resolve, reject) {
      console.log(result.body)
      assert(result.res.statusCode === 201)
      assert(result.body.code === 201)
      assert(result.body.errors.length === 0)
      assert(result.body.saved === count)
      return resolve()
    })
  }
}

describe('push', function () {
  it('should send SINGLE, no header', function () {
    var buf = 'abcdef'
    return Fn.call('POST', 8000, '/example', buf)
    .then(shouldHaveWritten(1))
  })

  it('should send SINGLE, no data', function () {
    var buf = ''
    return Fn.call('POST', 8000, '/example', buf)
    .then(shouldHaveWritten(1))
  })

  it('should send SINGLE, with header', function () {
    var buf = 'abcdef'
    return Fn.call('POST', 8000, '/example', buf, [[modeHeader, 'single']])
    .then(shouldHaveWritten(1))
  })

  it('should send SINGLE, with separator', function () {
    var buf = 'abc\ndef'
    return Fn.call('POST', 8000, '/example', buf)
    .then(shouldHaveWritten(1))
  })

  it('should send MULTIPLE, without separator', function () {
    var buf = 'abcdef'
    return Fn.call('POST', 8000, '/example', buf, [[modeHeader, 'multiple']])
    .then(shouldHaveWritten(1))
  })

  it('should send MULTIPLE, with separator', function () {
    var buf = 'M abc\nM def\nM ghi\nM jkl'
    return Fn.call('POST', 8000, '/example', buf, [[modeHeader, 'multiple']])
    .then(shouldHaveWritten(4))
  })

  it('should send MULTIPLE, no data', function () {
    var buf = ''
    return Fn.call('POST', 8000, '/example', buf, [[modeHeader, 'multiple']])
    .then(shouldHaveWritten(1))
  })

  it.only('should send ATOMIC, without separator', function () {
    var buf = 'abcdefghijkl'
    return Fn.call('POST', 8000, '/example', buf, [[modeHeader, 'atomic']])
    .then(shouldHaveWritten(1))
  })

  it.only('should send ATOMIC, with separator', function () {
    var buf = 'A abc\nA def\nA ghi\nA jkl'
    return Fn.call('POST', 8000, '/example', buf, [[modeHeader, 'atomic']])
    .then(shouldHaveWritten(1))
  })

})
