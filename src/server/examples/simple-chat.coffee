events = require 'events'
async = require 'async'

module.exports = (server) ->
	server.use 'deps'
	server.use 'cell'
	server.use 'rpc'
	server.use 'publish'

	{cell,deps,rpc} = server

	# A stateful single threaded server logic
	class CellGuest extends events.EventEmitter
		constructor : (@id) ->
		init : (cb) -> cb()
		destroy : (cb) ->
			@emit 'close'
			cb()
		send : (json) ->
			console.log 'trying to send', json

	class CellServer extends events.EventEmitter
		public : ['subscribe','unsubscribe']

		session : (id) -> @guests[id]

		constructor : (@cell,@GuestClass=CellGuest) ->
			@guests = {}			
			@deps = deps
			(require '../publish') @
		
		join : (client,cb) ->
			return cb('already joined') if @guests[client]
			guest = @guests[client] = new @GuestClass(client)
			guest.init(cb)			

		leave : (client,cb) ->			
			return cb('not joined') unless @guests[client]			

			async.series [
				(cb) => @guests[client].destroy cb
				(cb) => 
					delete @guests[client]
					cb()
			], cb

		invoke : (method,node,args...,cb) ->
			switch method
				when '+node' 
					node.__sessions = []
					cb()
				when '-node'  
					jobs = node.__sessions.map (x) => (cb) => @leave(x,cb)
					delete node.__sessions
					async.parallel jobs, cb					
				when '+session' 
					session = args[0]
					node.__sessions.push(session)
					@join(session,cb)
				when '-session' 
					session = args[0]
					i = node.__sessions.indexOf(session)
					node.__sessions.splice i, 1
					@leave(session,cb)
				else
					unless @[method]
						cb('no such method')
					else
						[session,args...] = args
						@[method].call @, @session(session), args..., cb

	class CellInstance extends CellServer
		public : ['chat','fetch','subscribe','unsubscribe']
		
		constructor : (@cell) ->
			theServer = @

			class ChatGuest extends CellGuest
				constructor : ->
					super

					@cursor = 0
					@longpoll = null

					@say 'joined'

				destroy : (cb) ->
					@say 'left'
					@longpoll?()
					@longpoll = null

					super cb

				say : (what) ->
					theServer.enqueue @id, what

			super @cell, ChatGuest

			@text = []
			@channel = "chatlog:#{@cell}"		
			
		init : (cb) ->
			console.log 'chat room open', @cell
			@publish 'chat', (client,old) => 
				deps.read @				
				text:@text
			cb()

		destroy : (cb) ->
			console.log 'chat room closed', @cell
			@unpublish @channel
			cb()


		## Client related ##
		init_client : (client,cell,interfaces) ->
			client.chats ?= {}
			client.chats[cell] = interfaces
			deps.write client

		uninit_client : (client,cell) ->
			delete client.chats[cell]
			deps.write client
		
		## Logic ##
		enqueue : (who,what...) ->
			@text.push [who,what...]
			@invalidate()

		invalidate : ->
			deps.write @
			for k,v of @guests
				if v.longpoll
					buffer = @text.slice(v.cursor)				
					v.cursor = @text.length					
					v.longpoll null, buffer
					v.longpoll = null
		
		## public 
		chat : (client,msg,cb) ->			
			client.say msg			
			cb()

		# long polling
		fetch : (client,cb) ->
			return cb('invalid user') unless @guests[client]

			if @guests[client].cursor == @text.length
				return cb('only one longpoll') if @guests[client].longpoll 
				
				@guests[client].longpoll = cb
			else				
				v = @guests[client]
				buffer = @text.slice(v.cursor)								
				v.cursor = @text.length
				cb null, buffer
	
	config = 
		name : 'chat'
		user_class : CellInstance
		session : (x) -> x.id

	cell.server config, ->
		console.log 'simple-chat server'.bold

	cell_client = cell.client config, ->
		console.log 'simple-chat client'.bold
	
	rpc.chat =
		open : (client,cell,cb) ->			
			cell_client.cell(cell).join(client,cb)

		__expand__ : (client) ->
			client.chats
