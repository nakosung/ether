events = require 'events'
fs = require 'fs'
_ = require 'underscore'
require 'colors'
async = require 'async'

class Client extends events.EventEmitter
	constructor : (@id,@conn) ->		
		@conn.on 'data', (msg) =>
			@emit 'raw', msg			
			data = null
			try				 
				data = JSON.parse(msg)								
			catch e
				
			if data
				@emit 'data', data

	destroy : ->
		@emit 'close'		

	toString : -> "client:#{@id}"

	sendraw : (raw) -> @conn.write raw
	send : (json) -> @sendraw JSON.stringify json

class Server extends events.EventEmitter
	constructor : (@ClientClass = Client) ->		
		@nextClientId = 0
		@dir = '.'
		@clients = []		
		@inits = []
		
		@all = 
			sendraw : (raw) => client.sendraw raw for client in @clients
			send : (data) => client.send data for client in @clients

		@initSockjs()
		@initExpress()	

	initSockjs : ->
		sockjs = require 'sockjs'
		@sockjs = sockjs.createServer log:-> # silent sock.js!
		@sockjs.on 'connection', (conn) => 
			client = new @ClientClass("#{@id}:#{@nextClientId++}",conn)			

			client.on 'raw', (raw) => @emit 'client:raw', client, raw
			client.on 'data', (data) => @emit 'client:data', client, data
			conn.once 'close', => 
				client.destroy()
				i = @clients.indexOf client
				@clients.splice i,1
				@emit 'client:leave', client

			@on 'client-src:changed', => client.sendraw 'client-src:changed'

			@clients.push client			
			@emit 'client:join', client

	initExpress : ->
		express = require 'express'		
		http = require 'http'

		fileUpdated = =>
			unless @timer
				@timer = setTimeout (=>
					@timer = null
					@emit 'client-src:changed'
					), 100					

		@app = express()		
		@app.use '/', express.static('public')
		@app.use '/lib', express.static('lib/client')

		fs.watch @dir + '/public', fileUpdated
		fs.watch @dir + '/lib/client', fileUpdated

		# workaround for sock.js + express impedence mismatch
		@server = require('http').createServer @app		
		@sockjs.installHandlers @server, {prefix:'/sockjs'}

	use : (plugin,opt) ->
		if _.isString plugin			
			@use (require @dir + '/' + plugin), opt
		else
			unless plugin.init?
				plugin.init = true				
				plugin.call(@,@,opt)

	listen : (port = 3338) ->		
		@server.listen 3338
		console.log 'ether'.green.bold, 'listens at port', String(port).red.bold

	cleanup : (fn) ->
		@cleanups ?= []
		@cleanups.push(fn)

	exit : (cb) ->
		console.log 'exit!'
		if @cleanups?
			async.parallel @cleanups, cb				
		else
			cb()
		
module.exports = (plugins,opts) ->
	main = (plugins,opts) ->		
		server = new Server		
		server.id = opts.id
		plugins.map (x) -> server.use x, opts?[x]

		# process.on 'SIGUSR2', ->
		# 	server.exit ->
		# 		process.kill process.pid, 'SIGUSR2'

		process.on 'SIGINT', ->
			server.exit ->
				process.exit()

		server

	if opts.cluster		
		if cluster.isMaster
			[1..4].map -> cluster.fork()
			undefined
		else
			_.extend opts, id:cluster.worker.id
			main plugins, opts
	else
		_.extend opts, id:'standalone'
		main plugins, opts

