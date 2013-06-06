express = require 'express'		
http = require 'http'
watch = require 'node-watch'
_ = require 'underscore'

module.exports = (server,opts) ->
	@use 'sockjs'

	timer = null
	fileUpdated = (f) =>
		console.log 'client file changed'.bold.red, f.bold.green
		@emit 'client-src:changed'

	fileUpdated = _.debounce fileUpdated, 500					

	app = express()		
	app.use '/', express.static('public')
	app.use '/lib', express.static('build/public')

	watch @dir + '/public', fileUpdated
	watch @dir + '/build/public', fileUpdated

	# workaround for sock.js + express impedence mismatch
	httpServer = require('http').createServer app		
	@sockjs.installHandlers httpServer, {prefix:'/sockjs'}

	init : (cb) ->
		port = opts?.port or 3338
		httpServer.listen port
		console.log 'ether'.green.bold, 'listens at port', String(port).red.bold
		cb()