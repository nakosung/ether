# TODO : replace sub/pub of cell req with redis counter.

_ = require 'underscore'
net = require 'net'
async = require 'async'
events = require 'events'
assert = require 'assert'
grace = require '../grace'
bidir_rpc = require '../bidir_rpc'

# this module deals with 'THE PARTIAL' : server-cell --- {shared connection} --- client-cell

# Whole picture is like below
# 	Client-aware server-cell --- server-cell --- {shared connection} --- client-cell --- client-aware client-cell

module.exports = (server) ->
	server.use 'redis'

	{redis} = server	
	{pub} = redis				

	# my channels!
	class TissueCommon extends events.EventEmitter
		constructor : (@config) ->
			@sub = require('redis').createClient()

		sub_redis : (handler,cb) ->		
			msg_proc = {}
			for k,v of handler			
				msg_proc[@config.id(k)] = v			

			# message handler
			@sub.on 'message', (channel, message) =>	
				msg_proc[channel]?(message)

			# subscribe to all channels
			_.keys(msg_proc).map (x) => @sub.subscribe x

			subs = _.keys(msg_proc)
			@sub.on 'subscribe', (ch,cont) ->
				i = subs.indexOf(ch)
				if i >= 0
					subs.splice(i,1)
					if subs.length == 0
						cb()
	
	# Tissue server manages group of membranes which holds a cell-server inside it.
	# It also connects other remote tissue clients via Connection which resides on each client.

	# Relationship
	#	Tissue server has N membranes, M connections. NxM cross-connections should be handled carefully.

	class TissueServer extends TissueCommon
		constructor : (@config) ->
			super @config

			@membranes = {}			

			@id = @config.id('server',server.id)			

		toString : -> @id

		ready_to_serve : ->
			@has_enough_capacity_to_serve_more() and not @is_shutting_down

		# TODO : important piece for load balancing
		has_enough_capacity_to_serve_more : ->
			true

		init : (cb) ->						
			async.series [
				(cb) => @init_net cb			
				(cb) =>
					handler = 
						sub : (message) =>
							cell = message
							@replyToClientSub(cell)				

						unsub : (message) =>
							cell = message
							@replyToClientUnsub(cell)

					@sub_redis handler, cb
			], cb						

		shutdown : (cb) ->
			@is_shutting_down = true

			# release all cells
			jobs = []
			for k, v of @membranes
				jobs.push (cb) => v.release(cb)

			@sub.end()

			async.parallel jobs, cb		

		replyToClientSub : (cell) ->			
			membrane = @membranes[cell]
			unless membrane
				# we aren't ready
				return unless @ready_to_serve()

				@createMembrane(cell)
			else
				membrane.sub()				

		replyToClientUnsub : (cell) ->
			@membranes[cell]?.unsub()				

		createMembrane : (cell) ->
			class PseudoMembrane
				constructor :      -> @subs = 1
				sub 		:      -> @subs++
				unsub 		:      -> @subs--
				release 	: (cb) -> @relFn = cb
				clear 		:      -> @relFn?()

			@membranes[cell] = new PseudoMembrane()
			main = =>
				membrane = new @config.Membrane @config, @				
				membrane.once 'open', =>						
					pseudo = @membranes[cell]						
					@membranes[cell] = membrane						

					# if unsub occurred during initialization
					pseudo.clear()
					if pseudo.subs == 0
						membrane.swapout()
					else 							
						for [1..pseudo.subs] 
							membrane.sub()

					pub.publish @config.id('open'), JSON.stringify({cell:cell,endpoint:@endpoint})
					@emit 'cell', membrane
					@emit 'add', cell
					
				membrane.once 'close', =>					
					delete @membranes[cell]
					@emit 'remove', cell								

				# if it succeeds, 
				membrane.open cell, (err) ->						
					# failed to open
					membrane.removeAllListeners() if err
					
			main cell

		init_net : (cb) ->						
			handler = (c) =>				
				bi = bidir_rpc(c)

				bi.once 'line', (remote_id) =>				
					# provide some remote-local storage
					cells = {}			

					class Node extends events.EventEmitter
						constructor : (@cell,@remote_id) ->	
							@methods = {}
						destroy : (cb) ->
							if @emit 'shutdown'
								@once 'close', cb
							else
								delete cells[@cell]
								@emit 'close'
								@removeAllListeners()
								cb()
						invoke : (args...) -> grace.invoke.call @, args...
						invoke_remote : (args...,cb) -> bi.invoke(@cell,args...,cb)

					notifyConnectionClosed = =>					
						for k,v of trs
							v('disconnected')
						trs = {}

						jobs = []
						for k,v of cells 
							jobs.push (cb) -> v.destroy(cb)
						async.parallel jobs, ->

					c.on 'close', notifyConnectionClosed

					bi.on 'invoke', (cell,args...,cb) =>
						membrane = @membranes[cell]
						unless membrane
							cb('no such cell here:',cell)
						else
							remote = cells[cell]
							unless remote
								remote = cells[cell] = new Node cell, remote_id
								membrane.once 'close', ->
									bi.invoke cell, '-cell', ->
								membrane.emit 'node', remote
							#console.log 'INVOKE'.bold, method, args...
							remote.invoke args..., cb

			@net = net.createServer handler		
			@endpoint = port:8124

			@net.on 'error', (e) =>	
				if e.code == "EADDRINUSE"
					@endpoint.port++
					attemptListen() 					

			attemptListen = () =>
				@net.listen @endpoint.port								
			attemptListen()				
			cb()	

	class TissueClient extends TissueCommon
		constructor : (@config) ->
			super @config

			@connections = {}	
			@cells = {}			

		init : (cb) ->
			endpoint_to_key = (endpoint) -> JSON.stringify endpoint

			handler = 
				open : (message) =>
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

				close : (message) =>
					{cell,endpoint} = JSON.parse(message)
					client = @cells[cell]

					if client
						key = endpoint_to_key(endpoint)
						connection = @connections[key]
						connection.leave client if connection
						# do not close the connection 
			@sub_redis handler, cb

		shutdown : ->
			@sub.end()

			for k,v of @connections
				v.destroy()

		cell : (cell) ->
			c = @cells[cell]
			unless c
				c =	@cells[cell] = new CellClient(@,@config,cell)
				@emit 'cell', c
			c

		activate : (cell) ->			
			pub.sadd @config.id(cell,'subs'), server.id
			pub.publish @config.id('sub'), cell

		deactivate : (cell) ->						
			pub.srem @config.id(cell,'subs'), server.id
			pub.publish @config.id('unsub'), cell

	# Connection is between TissueServer and TissueClient, resides on client.
	class Connection extends events.EventEmitter
		constructor : (@endpoint) ->
			@clients = {}
			@online = false		

		join : (client) ->
			return if @clients[client.cell]

			client.set_connection @

			@clients[client.cell] = client

		leave : (client) ->
			return unless @clients[client.cell]
			
			client.set_connection null

			delete @clients[client.cell]

		connect : (cb) ->
			return cb('pending connection or already connected') if @net

			async.series [				
				(cb) => 
					@net = net.connect @endpoint, cb
				(cb) => 
					@net.write server.id
					@net.write "\r\n"

					@bi = bidir_rpc(@net)

					@online = true						
					@bi.on 'invoke', (cell,args...,cb) =>
						cell = @clients[cell]
						return cb('no such cell here') unless cell

						if args[0] == '-cell'
							@leave(cell,cb)
						else
							cell.invoke args..., cb						

					@net.once 'end', =>
						@bi = null
						@online = false
						@destroy()

					@emit 'open'

					cb()
			], cb

		destroy : ->
			for k,v of @clients
				@leave v

			if @net
				@net.end()
				@net = null		

			@emit 'close'
			@removeAllListeners()

		is_online : -> @online

		invoke_remote : (cell,method,args...,cb) ->
			return cb('cell network not available') unless @bi

			@bi.invoke cell, method, args..., cb

	class CellClient extends events.EventEmitter
		constructor : (@tissue,@config,@cell) ->			
			@active = false			
			@methods = {}

		destroy : (cb) ->
			grace.shutdown.call @, =>
				@deactivate cb if @active				
				@connection.leave(@) if @connection
				@removeAllListeners()
				cb()				
	
		is_online : ->
			@connection?.is_online()

		set_connection : (connection) ->			
			return if connection == @connection

			fn = =>
				if @connection?.is_online()
					@emit 'online'
				else
					@emit 'offline'

			if @connection? 
				old_conn = @connection
				@connection = null
				if old_conn.is_online()
					old_conn.removeListener 'open', fn
					old_conn.removeListener 'close', fn
					@emit 'offline'
			else 
				@connection = connection
				connection.on 'open', fn
				connection.on 'close', fn
				@emit 'online' if connection.is_online()

		invoke_remote : (method,args...,cb) ->			
			return cb('cell provider not available') unless @connection

			@connection.invoke_remote @cell, method, args..., cb

		invoke : (args...) ->
			grace.invoke.call @, args...

		activate : ->
#			console.log 'activate'
			assert(not @active)
			@active = true
			@tissue.activate @cell

		deactivate : ->
#			console.log 'deactivate'
			assert(@active)
			@active = false
			@tissue.deactivate @cell

	TissueServer : TissueServer
	TissueClient : TissueClient
	