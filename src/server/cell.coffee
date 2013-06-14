_ = require 'underscore'
async = require 'async'
events = require 'events'
assert = require 'assert'

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
			async.series [
				(cb) -> tissue.init cb
				(cb) -> cb(tissue)
			], cb
		client : (config,cb) ->
			config = configify config			
			tissue = new TissueClient configify config
			async.series [
				(cb) -> tissue.init cb
				(cb) -> cb(tissue)
			], cb

	