_ = require 'underscore'
net = require 'net'
async = require 'async'
events = require 'events'
carrier = require 'carrier'

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
	
	class TissueServer extends TissueCommon
		constructor : (@config) ->
			super @config

			@membranes = {}			
			
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
				class PseudoMembrane
					constructor : ->
						@subs = 1
					sub : ->
						@subs++
					unsub : ->
						@subs--
					release : (cb) ->						
						@relFn = cb
					clear : ->											
						@relFn?()

				@membranes[cell] = new PseudoMembrane()
				main = =>
					# we aren't ready
					return unless @ready_to_serve()

					membrane = new @config.Membrane @config
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
						@emit 'add', cell
						
					membrane.once 'close', =>
						delete @membranes[cell]
						@emit 'remove', cell								

					# if it succeeds, 
					membrane.open cell, (err) ->						
						# failed to open
						membrane.removeAllListeners() if err
						
				main cell
			else
				membrane.sub()				

		replyToClientUnsub : (cell) ->
			@membranes[cell]?.unsub()				

		init_net : (cb) ->			
			handler = (c) =>				
				my_carrier = carrier.carry(c)
				my_carrier.on 'line', (data) =>
					[cell,trid,method,args...] = JSON.parse(data)
					cb = (r...) ->
						c.write JSON.stringify [trid,r...]
						c.write "\r\n"

					membrane = @membranes[cell]?.server				
					unless membrane
						cb('no such cell here')
					else 
						unless membrane[method]
							cb('no such method')
						else
							membrane[method].call membrane, args..., cb

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
			@cells[cell] ?= new @config.client_class @, @config, cell

		activate : (cell,cb) ->			
			async.parallel [
				(cb) => pub.sadd @config.id(cell,'subs'), server.id, cb
				(cb) => pub.publish @config.id('sub'), cell, cb
			], cb

		deactivate : (cell,cb) ->			
			async.parallel [
				(cb) => pub.srem @config.id(cell,'subs'), server.id, cb
				(cb) => pub.publish @config.id('unsub'), cell, cb
			], cb

	# Connection is between TissueServer and TissueClient, resides on client.
	class Connection extends events.EventEmitter
		constructor : (@endpoint) ->
			@trid = 0
			@trs = {}
			@clients = []						

		join : (client) ->
			return if @clients.indexOf(client) >= 0

			client.set_connection @

			@clients.push client			

		leave : (client) ->
			i = @clients.indexOf(client)
			return if i < 0

			client.set_connection null

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

					@emit 'open'

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
			@removeAllListeners()

		is_online : -> @net?

		invoke : (cell,method,args...,cb) ->
			return cb('cell network not available') unless @net

			trid = @trid++
			packet = [cell,trid,method,args...]
			@trs[trid] = cb			
			
			@net.write JSON.stringify(packet)
			@net.write "\r\n"



	TissueServer : TissueServer
	TissueClient : TissueClient