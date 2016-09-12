'use strict'

global.Promise = require('bluebird')
var Fn = require('./fn')
var assert = require('assert')
var request = require('superagent')

var modeHeader = 'newque-mode'
var idHeader = 'newque-msg-id'

var shouldHaveWritten = function (count) {
  return function (result) {
    return new Promise(function (resolve, reject) {
      assert(result.res.statusCode === 201)
      assert(result.body.code === 201)
      assert(result.body.errors.length === 0)
      assert(result.body.saved === count)
      return resolve()
    })
    .catch(function (err) {
      console.log(result.res.statusCode)
      console.log(result.body)
      throw err
    })
  }
}

var shouldFail = function (count) {
  return function (result) {
    return new Promise(function (resolve, reject) {
      assert(result.res.statusCode === 400)
      assert(result.body.code === 400)
      assert(result.body.errors.length > 0)
      assert(result.body.saved === count)
      console.log(result.body.errors)
      return resolve()
    })
    .catch(function (err) {
      console.log(result.res.statusCode)
      console.log(result.body)
      throw err
    })
  }
}

describe('Push', function () {
  describe('Single', function () {
    it('No header', function () {
      var buf = 'abcdef'
      return Fn.call('POST', 8000, '/example', buf)
      .then(shouldHaveWritten(1))
    })

    it('No data', function () {
      var buf = ''
      return Fn.call('POST', 8000, '/example', buf)
      .then(shouldHaveWritten(1))
    })

    it('With header', function () {
      var buf = 'abcdef'
      return Fn.call('POST', 8000, '/example', buf, [[modeHeader, 'single']])
      .then(shouldHaveWritten(1))
    })

    it('With separator', function () {
      var buf = 'abc\ndef'
      return Fn.call('POST', 8000, '/example', buf)
      .then(shouldHaveWritten(1))
    })

    it('With bad header', function () {
      var buf = 'abcdef'
      return Fn.call('POST', 8000, '/example', buf, [[modeHeader, 'invalid header']])
      .then(shouldFail(0))
    })
  })

  describe('Multiple', function () {
    it('Without separator', function () {
      var buf = 'abcdef'
      return Fn.call('POST', 8000, '/example', buf, [[modeHeader, 'multiple']])
      .then(shouldHaveWritten(1))
    })

    it('With separator', function () {
      var buf = 'M abc\nM def\nM ghi\nM jkl'
      return Fn.call('POST', 8000, '/example', buf, [[modeHeader, 'multiple']])
      .then(shouldHaveWritten(4))
    })

    it('No data', function () {
      var buf = ''
      return Fn.call('POST', 8000, '/example', buf, [[modeHeader, 'multiple']])
      .then(shouldHaveWritten(1))
    })

    it('Empty messages', function () {
      var buf = '\n\na\n'
      return Fn.call('POST', 8000, '/example', buf, [[modeHeader, 'multiple']])
      .then(shouldHaveWritten(4))
    })
  })

  describe('Atomic', function () {
    it('Without separator', function () {
      var buf = 'abcdefghijkl'
      return Fn.call('POST', 8000, '/example', buf, [[modeHeader, 'atomic']])
      .then(shouldHaveWritten(1))
    })

    it('With separator', function () {
      var buf = 'A abc\nA def\nA ghi\nA jkl'
      return Fn.call('POST', 8000, '/example', buf, [[modeHeader, 'atomic']])
      .then(shouldHaveWritten(1))
    })

    it('Empty messages', function () {
      var buf = '\n\nz\n'
      return Fn.call('POST', 8000, '/example', buf, [[modeHeader, 'atomic']])
      .then(shouldHaveWritten(1))
    })
  })

  describe('Custom IDs', function () {
    it('Without separator, single mode', function () {
      var buf = 'A abc\nA def\nA ghi\nA jkl'
      return Fn.call('POST', 8000, '/example', buf, [[modeHeader, 'single'], [idHeader, 'id1']])
      .then(shouldHaveWritten(1))
    })

    it('With separator, single mode', function () {
      var buf = 'A abc\nA def\nA ghi\nA jkl'
      return Fn.call('POST', 8000, '/example', buf, [[modeHeader, 'single'], [idHeader, 'id1,id2']])
      .then(shouldHaveWritten(1))
    })

    it('Without separator', function () {
      var buf = 'abcdef'
      return Fn.call('POST', 8000, '/example', buf, [[modeHeader, 'single'], [idHeader, 'id10,id11,id12,id13']])
      .then(shouldHaveWritten(1))
    })

    it('With separator', function () {
      var buf = 'A abc\nA def\nA ghi\nA jkl'
      return Fn.call('POST', 8000, '/example', buf, [[modeHeader, 'multiple'], [idHeader, 'id10,id11,id12,id13']])
      .then(shouldHaveWritten(4))
    })

    it('With separator, non-matching lengths 1', function () {
      var buf = 'A abc\nA def\nA ghi\nA jkl'
      return Fn.call('POST', 8000, '/example', buf, [[modeHeader, 'multiple'], [idHeader, 'id20,id21,id22']])
      .then(shouldFail(0))
    })

    it('With separator, non-matching lengths 2', function () {
      var buf = 'A abc\nA def\nA ghi'
      return Fn.call('POST', 8000, '/example', buf, [[modeHeader, 'multiple'], [idHeader, 'id30,id31,id32,id33']])
      .then(shouldFail(0))
    })

    it('With separator, empty IDs 1', function () {
      var buf = 'A abc\nA def\nA ghi'
      return Fn.call('POST', 8000, '/example', buf, [[modeHeader, 'multiple'], [idHeader, 'id40,id41,id42,']])
      .then(shouldFail(0))
    })

    it('With separator, empty IDs 2', function () {
      var buf = 'A abc\nA def\nA ghi'
      return Fn.call('POST', 8000, '/example', buf, [[modeHeader, 'multiple'], [idHeader, 'id50,id51,,id52,id53']])
      .then(shouldFail(0))
    })

    it('With separator, atomic', function () {
      var buf = 'A abc\nA def\nA ghi'
      return Fn.call('POST', 8000, '/example', buf, [[modeHeader, 'atomic'], [idHeader, 'id60,id61,id62,']])
      .then(shouldHaveWritten(1))
    })

    it('With separator, skip existing', function () {
      var buf = 'A abc\nA def\nA ghi'
      return Fn.call('POST', 8000, '/example', buf, [[modeHeader, 'multiple'], [idHeader, 'id70,id70,id1']])
      .then(shouldHaveWritten(1))
    })
  })

})
