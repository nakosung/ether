events = require 'events'
_ = require 'underscore'
async = require 'async'
require 'colors'

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

	publish : (channel,message) -> @send pub:[channel,message]

class Server extends events.EventEmitter
	constructor : (@ClientClass = Client) ->		
		@nextClientId = 0
		@dir = '.'
		@clients = []		
		@inits = []
		
		@all = 
			sendraw : (raw) => client.sendraw raw for client in @clients
			send : (data) => client.send data for client in @clients
	
	use : (plugin,opt) ->
		if _.isString plugin			
			@use (require @dir + '/' + plugin), opt
		else
			unless plugin.init?
				plugin.init = true				
				r = plugin.call(@,@,opt)
				@inits.push r.init if _.isFunction(r?.init)

	initialize : (cb) ->				
		async.series @inits, cb	

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

