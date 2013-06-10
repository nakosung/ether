module.exports = (server) ->
	server.use 'deps'
	server.use 'cell'
	server.use 'rpc'

	{cell,deps,rpc} = server

	class CellInstance 
		constructor : (@cell) ->
			@users = {}
			@text = []
			
		init : (cb) ->
			console.log 'chat room open', @cell
			cb()
		
		client : (client) ->
			client.id

		init_client : (client,cell,interfaces) ->
			client.chats ?= {}
			client.chats[cell] = interfaces
			deps.write client

		uninit_client : (client,cell) ->
			delete client.chats[cell]
			deps.write client

		destroy : (cb) ->
			console.log 'chat room closed', @cell
			cb()

		invalidate : ->
			for k,v of @users
				if v.longpoll
					buffer = @text.slice(v.cursor)				
					v.cursor = @text.length					
					v.longpoll null, buffer
					v.longpoll = null

		join : (client,cb) ->
			return cb('already joined') if @users[client]
			@users[client] = 
				cursor : 0
				longpoll : null
			@text.push [client,"joined"]
			@invalidate()
			cb()

		leave : (client,cb) ->			
			return cb('not joined') unless @users[client]			

			@text.push [client,"left"]
			@invalidate()
			@users[client].longpoll?()
			delete @users[client]
			cb()

		chat : (client,msg,cb) ->
			return cb('invalid user') unless @users[client]

			@text.push [client, msg]
			@invalidate()
			cb()		

		# long polling
		fetch : (client,cb) ->
			return cb('invalid user') unless @users[client]

			if @users[client].cursor == @text.length
				@users[client].longpoll = cb
			else
				buffer = @text.slice(@users[client].cursor)								
				@users[client].cursor = @text.length
				cb null, buffer
	
	config = 
		name : 'chat'
		user_class : CellInstance
	
	cell.server config, ->
		console.log 'simple-chat'.bold

	cell_client = cell.client config
	
	rpc.chat =
		open : (client,cell,cb) ->			
			cell_client.cell(cell).join(client,cb)

		__expand__ : (client) ->
			client.chats
