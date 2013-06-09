_ = require 'underscore'

module.exports = (server) ->
	server.use 'rpc'

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

	{rpc,deps} = server

	Cells = {}

	class CellInstance
		constructor : (@cell) ->

		hello : (client,msg,cb) ->
			console.log 'cell instance says hello', msg
			cb()	

	class CellClient
		constructor : (@instance,cell) ->
			@cell = cell
			@clients = {}

			@create_interface()

		destroy : ->

		create_interface : ->
			@interface = 
				close : (client,cb) =>
					@leave(client,cb)
			_.keys(@instance.prototype).forEach (method) =>
				@interface[method] = (args...) =>
					@invoke method, args...

		join : (client,cb) ->
			return cb('already open') if @clients[client.id] >= 0

			@clients[client.id] = true
			client.cells ?= {}
			client.cells[@cell] = @interface
			console.log client.cells
			deps.write client
			cb()

		invoke : (method,args...,cb) ->
			cb('not available')

		leave : (client,cb) ->
			return cb('closed') unless client.cells[@cell]

			delete client.cells[@cell]
			delete @clients[client.id]
			deps.write client
			cb()

	
	rpc.cell =
		open : (client,cell,cb) ->
			Cells[cell] ?= new CellClient CellInstance, cell
			Cells[cell].join(client,cb)

		__expand__ : (client) ->
			client.cells


