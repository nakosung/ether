# collection of some commonly used patterns 
assert = require 'assert'
_ = require 'underscore'

module.exports = 
	shutdown : (cb) ->
		if @emit 'shutdown'
			@once 'close', cb
		else
			@emit 'close'
			@removeAllListeners()
			cb()
	invoke : (method,args...,cb) ->
		assert _.isFunction(cb)
		m = @methods[method]
		unless m		
			m = @methods['*'] 
			if m
				return m.call @, method, args..., cb
		return cb('no such method in membrane:'+method) unless m
		m.call @, args...,cb