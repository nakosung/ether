_ = require 'underscore'
net = require 'net'
async = require 'async'
events = require 'events'
carrier = require 'carrier'

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

	server.use 'deps'
	server.use 'rpc'
	server.use 'redis'
	server.use 'token'

	{rpc,deps,redis} = server	
	{sub,pub} = redis	

	class TissueServer extends events.EventEmitter
		constructor : (@config) ->
			@cells = {}

		ready_to_serve : ->
			@has_enough_capacity_to_serve_more() and not @is_shutting_down

		# TODO : important piece for load balancing
		has_enough_capacity_to_serve_more : ->
			true

		shutdown : (cb) ->
			@is_shutting_down = true

			# release all cells
			for k, v of @cells
				@release_cell v

			fn = =>
				if _.keys(@cells).length == 0
					cb()

			@on 'close-cell', fn

		init_redis : (cb) ->
			sub.on 'message', (channel, message) =>
				if channel == @config.id('sub')
					cell = message

					fn = (taker,cb) =>
						console.log 'take!!!', taker
						return cb('no way') unless taker == "TIMEOUT" or not taker? # null taker is DESTROYER!

						cell_server = @cells[cell]
						if cell_server
							@clear_swapout cell_server
							delete @cells[cell]
							cell_server.destroy(cb)
							@emit 'close-cell', cell
						else
							cb()					

					cell_server = @cells[cell]
					unless cell_server
						if @ready_to_serve()
							token = @config.id(cell)
							console.log 'server request'.bold.red, token
							async.series [
								(cb) => server.acquireToken server.id, token, fn, cb
								(cb) => @init_cell(cell,cb)
							], -> 
					else
						@add_client(cell_server)						

				if channel == @config.id('unsub')
					cell = message

					cell_server = @cells[cell]
					if cell_server
						cell_server.clients--

						if cell_server.clients == 0
							@swapout cell_server

				sub.subscribe @config.id('sub')
				sub.subscribe @config.id('unsub')
			cb()

		init_cell : (cell,cb) ->
			cell_server = @cells[cell] = new @config.user_class(cell)
			cell_server.clients = 1
			async.series [
				(cb) => cell_server.init cb
				(cb) => pub.publish @config.id('open'), JSON.stringify {cell:cell,endpoint:@endpoint}
			], cb

		add_client : (cell_server) ->
			cell_server.clients++
			@clear_swapout(cell_server)			

		clear_swapout : (cell_server) ->
			cell_server.swappingout?()
			cell_server.swappingout = null

		release_cell : (cell_server) ->
			server.destroyToken @config.id(cell_server.cell), =>
				console.log 'released', @cells

		swapout : (cell_server) ->
			return if cell_server.swappingout
			fnSwapout = =>
				cell_server.swappingout = null				
				@release_cell(cell_server)
			timeout = setTimeout fnSwapout, @config.swapout_delay
			cell_server.swappingout = ->
				clearTimeout timeout

		init : (cb) ->			
			async.series [
				(cb) => @init_net cb
				(cb) => @init_redis cb
			], cb	

		init_net : (cb) ->			
			handler = (c) =>
				console.log 'client connected'
				c.once 'end', ->
					console.log 'client disconnected'
				my_carrier = carrier.carry(c)
				my_carrier.on 'line', (data) =>
					[cell,trid,method,args...] = JSON.parse(data)
					cb = (r...) ->
						c.write JSON.stringify [trid,r...]
						c.write "\r\n"

					cell_server = @cells[cell]					
					unless cell_server
						cb('no such cell here')
					else 
						unless cell_server[method]
							cb('no such method')
						else
							cell_server[method].call cell_server, args..., cb

			@net = net.createServer handler		
			@endpoint = port:8124			

			attemptListen = () =>
				@net.listen @endpoint.port
				@net.on 'error', (e) =>	
					if e.code == "EADDRINUSE"
						@endpoint.port++
						attemptListen() 					
			attemptListen()				
			cb()	

	class TissueClient
		constructor : (@config) ->
			@connections = {}	
			@cells = {}

			endpoint_to_key = (endpoint) -> JSON.stringify endpoint

			sub.on 'message', (channel,message) =>
				if channel == @config.id('open')
					{cell,endpoint} = JSON.parse(message)
					client = @cells[cell]

					if client
						key = endpoint_to_key(endpoint)
						connection = @connections[key]

						unless connection
							connection = @connections[key] = new Connection endpoint
							connection.once 'close', =>
								delete @connections[key]
							connection.connect ->

						connection.join client

				if channel == @config.id('close')
					{cell,endpoint} = JSON.parse(message)
					client = @cells[cell]

					if client
						key = endpoint_to_key(endpoint)
						connection = @connections[key]

						if connection
							connection.leave client


			sub.subscribe @config.id('open')

		cell : (cell) ->
			@cells[cell] ?= new CellClientEx @config, cell

	class Connection extends events.EventEmitter
		constructor : (@endpoint) ->
			@trid = 0
			@trs = {}
			@clients = []						

		join : (client) ->
			return if @clients.indexOf(client) >= 0

			client.connection = @

			@clients.push client

			if @net
				client.init_net()

		leave : (client) ->
			i = @clients.indexOf(client)
			return if i < 0

			client.connection = null

			@clients.splice i, 1

		connect : (cb) ->
			return cb('connected') if @net

			async.series [				
				(cb) => 
					@net = net.connect @endpoint, cb
				(cb) => 	
					my_carrier = carrier.carry(@net)				
					my_carrier.on 'line', (data) =>
						# if destroyed?
						return unless @net

						[trid,result...] = JSON.parse(data)
						fn = @trs[trid]
						delete @trs[trid]
						fn?.apply null,result

					@net.once 'end', =>
						@destroy()

					@clients.forEach (c) -> c.init_net()					

					cb()
			], cb

		purgeAllTransactions : ->
			trs = @trs
			@trs = {}
			for k,v of trs
				v('disconnected')

		destroy : ->
			@purgeAllTransactions()

			@clients.forEach (client) =>
				@leave client

			if @net
				@net.end()
				@net = null		

			@emit 'close'

		invoke : (cell,method,args...,cb) ->
			return cb('cell network not available') unless @net

			trid = @trid++
			packet = [cell,trid,method,args...]
			@trs[trid] = cb			
			
			@net.write JSON.stringify(packet)
			@net.write "\r\n"

	class CellClient
		constructor : (@config,cell) ->
			@cell = cell					
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

		invoke : (method,args...,cb) ->			
			return cb('cell provider not available') unless @connection

			@connection.invoke @cell, method, args..., cb

		init_net : ->
			# called when network become up-and-running

		activate : (cb) ->
			return cb('invalid') if @active
			@active = true
			async.parallel [
				(cb) => pub.sadd @config.id(@cell,'subs'), server.id, cb
				(cb) => pub.publish @config.id('sub'), @cell, cb
			], cb

		deactivate : (cb) ->
			return cb('invalid') unless @active
			@active = false
			async.parallel [
				(cb) => pub.srem @config.id(@cell,'subs'), server.id, cb
				(cb) => pub.publish @config.id('unsub'), @cell, cb
			], cb

	class CellClientEx extends CellClient
		constructor : (@config,cell) ->
			super @config, cell

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
			tissue = new TissueServer config
			tissue.init cb
		client : (config) ->
			new TissueClient configify config

	