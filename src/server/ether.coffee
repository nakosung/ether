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
	constructor : (opts) ->		
		@id = opts.id
		@ClientClass = opts.ClientClass or Client
		@dir = opts.dir or '.'
		@nextClientId = 0		
		@clients = []		
		@inits = []

		@plugins = []
		
		@all = 
			sendraw : (raw) => client.sendraw raw for client in @clients
			send : (data) => client.send data for client in @clients
	
	use : (plugin,opt) ->
		if _.isString plugin
			@use (require @dir + '/' + plugin), opt
		else
			unless _.contains @plugins, plugin
				@plugins.push plugin
				r = plugin.call(@,@,opt)
				@inits.push r.init if _.isFunction(r?.init)
				r

	initialize : (cb) ->				
		async.series @inits, cb	

	cleanup : (fn) ->
		@cleanups ?= []
		@cleanups.push(fn)

	exit : (cb) ->		
		if @cleanups?
			async.parallel @cleanups, cb				
		else
			cb()
		
module.exports = (plugins,opts) ->
	main = (plugins,opts) ->		
		server = new Server	opts
		plugins.map (x) -> server.use x, opts?[x]

		server

	if opts.cluster
		cluster = require 'cluster'		
		if cluster.isMaster
			[1..4].map -> cluster.fork()
			undefined
		else
			_.extend opts, id:cluster.worker.id
			main plugins, opts
	else
		opts.id ?= 'standalone'
		main plugins, opts

