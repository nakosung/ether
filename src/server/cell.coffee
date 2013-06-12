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
	{TissueServer,TissueClient,CellClient} = server.use 'cell/nervtissue'		

	# Client-aware cell excluding RPC stuff
	class CellClientSession extends CellClient
		constructor : (@tissue, @config,cell) ->
			super @tissue, @config, cell

			@sessions = {}
			@numSessions = 0			

		invoke : (method,session,args...,cb) ->
			super method, session, args..., cb

		destroy : (cb) ->
			jobs = []
			for k,v of @sessions
				jobs.push (cb) => v.leave(cb)
			
			async.series [
				(cb) => async.parallel jobs, cb
				(cb) => super cb
			], cb

		join : (session,cb) ->
			id = session.id
			return cb('already open') if @sessions[id] 

			host = @

			class Agent extends events.EventEmitter
				constructor : (@session) ->					
					fnSessionCloseHandler = => @leave =>

					# TO ENSURE HARD PAIRING!
					host.sessions[id] = @
					@session.once 'close', fnSessionCloseHandler

					if host.numSessions++ == 0
						host.activate()

					add = -> host.emit 'add', session
					remove = -> host.emit 'remove', session

					if host.is_online() 
						add()

					host.on 'online', add
					host.on 'offline', remove

					@on 'close', =>
						host.removeListener 'online', add
						host.removeListener 'offline', remove

						if host.is_online()
							remove()

						delete host.sessions[id]
						@session.removeListener 'close', fnSessionCloseHandler
						if --host.numSessions == 0
							console.log 'all sessions dropped from cell client'
							host.deactivate()

				leave : (cb) ->
					@emit 'close'
					@removeAllListeners()

			agent = new Agent(session)			

			cb()

	class CellClientEx extends CellClientSession
		constructor : (@tissue, @config,cell) ->
			super @tissue, @config, cell

			@create_interface()	

			@on 'add', (client) =>
				@invoke '+session', client.id, ->
				@config.user_class::init_client client, @cell, @interface

			@on 'remove', (client) =>
				@config.user_class::uninit_client client, @cell
				@invoke '-session', client.id, ->

		create_interface : ->
			@interface = 
				close : (client,cb) => @clients[client.id].leave cb

			@config.user_class.prototype.public?.forEach (method) =>
				@interface[method] = (client,args...) =>
					@invoke method, client.id, args...


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

	