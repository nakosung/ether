express = require 'express'		
http = require 'http'
watch = require 'node-watch'

module.exports = (server,opts) ->
	@use 'sockjs'

	timer = null
	fileUpdated = =>
		unless timer
			timer = setTimeout (=>
				timer = null
				@emit 'client-src:changed'
				), 100					

	app = express()		
	app.use '/', express.static('public')
	app.use '/lib', express.static('lib/client')

	watch @dir + '/public', fileUpdated
	watch @dir + '/lib/client', fileUpdated

	# workaround for sock.js + express impedence mismatch
	httpServer = require('http').createServer app		
	@sockjs.installHandlers httpServer, {prefix:'/sockjs'}

	init : (cb) ->
		port = opts?.port or 3338
		httpServer.listen port
		console.log 'ether'.green.bold, 'listens at port', String(port).red.bold
		cb()