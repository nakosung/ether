_ = require 'underscore'
async = require 'async'
events = require 'events'

module.exports = (server) ->
	# cell can be a room in chat service, a zone in mmorpg world, and so on.
	# cell should be contained in one thread which is running on one node app.
	# this will eliminate all kinds of dirties related with concurrency.

	# all cells of a kind are homogeneous.

	# each cells represent their own domain of the problem.
	# eg) 
	#	cell 1 : chat-room 1, cell 2 : chat-room 2
	# 	cell 1 : world-zone [1,1] cell 2 : world-zone [1,2] 

	# interop among cells should be considered.
	# thus, the interface will be extended to non-user clients. (eg. other cell)

	# to improve network bandwidth and eliminate unnecessary redundancy
	# cells will accelerate muxed publish scheme.

	# FAULT TOLERANCY
	# cell can be dropped or down without a notice
	# latest state of cell may be cached into some kind of db (redis, mongo, ...)
	# so much of cells should remain as stateless.
	# this may help dynamic load balancing with cell-migration support.

	# eg) 
	#	critical persistent info of chat-service : list of participants
	#	critical persistent info of world-zone : list of entities (not activities)

	# TISSUE - CELL
	# A node process can host multiple cells.

	# Final interface
	# ---------------
	# rpc.cell.commands(client,cell,xxxx,cb)
	# publish 'cell', (client,id)
	# 
	# muxed version of pub/sub would be great for clients
	# to support this, pub/sub relationship is set between servers.

	# Cell interface will be reflected into rpc interface automatically.
	# The cell interface is actual service interface.

	# Sequence
	# subscribe service
	# rpc.cell.open
	# rpc.cell.xxx.
	
	{Membrane} = server.use 'cell/membrane'				
	{TissueServer,TissueClient} = server.use 'cell/nervtissue'	

	class CellClient
		constructor : (@tissue,@config,@cell) ->			
			@active = false

		destroy : (cb) ->
			async.series [
				(cb) => 
					if @active
						@deactivate cb
					else
						cb()
				(cb) =>
					if @connection
						@connection.leave(@)
					cb()				
			], cb

		set_connection : (connection) ->			
			@connection = connection
			if connection
				if connection.is_online()
					@init_net()				
				else
					connection.once 'open', =>
						@init_net()

		invoke : (method,args...,cb) ->			
			return cb('cell provider not available') unless @connection

			@connection.invoke @cell, method, args..., cb

		init_net : ->
			# called when network become up-and-running

		activate : (cb) ->
			return cb('invalid') if @active
			@active = true
			@tissue.activate(@cell,cb)

		deactivate : (cb) ->
			return cb('invalid') unless @active
			@active = false
			@tissue.deactivate(@cell,cb)

	class CellClientEx extends CellClient
		constructor : (@tissue, @config,cell) ->
			super @tissue, @config, cell

			@clients = []						

			@create_interface()	
		
		destroy : (cb) ->
			jobs = @clients.map (c) => (cb) => @leave(c,cb)
			
			async.series [
				(cb) => async.parallel jobs, cb
				(cb) => super cb
			], cb

		create_interface : ->
			@interface = 
				close : (client,cb) => @leave client, cb

			_.keys(@config.user_class.prototype).forEach (method) =>				
				return if ['constructor','destroy','init','client','init_client','uninit_client'].indexOf(method) >= 0

				@interface[method] = (client,args...) =>
					@invoke method, @config.user_class::client(client), args...				

		join : (client,cb) ->
			return cb('already open') if @clients.indexOf(client) >= 0

			@clients.push client

			@config.user_class::init_client client, @cell, @interface

			client.once 'close', => @leave client, =>

			unless @active
				@activate(cb)
			else
				cb()

		leave : (client,cb) ->
			i = @clients.indexOf(client)
			return cb('closed') unless i >= 0

			@config.user_class::uninit_client client, @cell

			@clients.splice i,1			

			if @clients.length == 0
				console.log 'all clients left from cell client'
				@deactivate(cb)
			else
				cb()

	configify = (config) ->
		o = _.extend {}, config
		o.id = (x...) ->
			[config.name,x...].join(':')
		o

	server.cell = 
		server : (config,cb) ->
			config = configify config
			config.swapout_delay ?= 5000 # default 5 sec
			config.Membrane = Membrane
			tissue = new TissueServer config
			tissue.init cb
			tissue
		client : (config,cb) ->
			config = configify config
			config.client_class = CellClientEx 
			tissue = new TissueClient configify config
			tissue.init cb
			tissue

	