module.exports = (server) ->
	server.use 'deps'
	server.use 'cell'
	server.use 'rpc'

	{cell,deps,rpc} = server

	# A stateful single threaded server logic
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

		enqueue : (who,what...) ->
			@text.push [who,what...]
			@invalidate()

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

			@enqueue client,"joined"						
			cb()

		leave : (client,cb) ->			
			return cb('not joined') unless @users[client]			

			@enqueue client,"left"
			
			@users[client].longpoll?()
			delete @users[client]

			cb()

		chat : (client,msg,cb) ->
			return cb('invalid user') unless @users[client]

			@enqueue client, msg
			
			cb()		

		# long polling
		fetch : (client,cb) ->
			return cb('invalid user') unless @users[client]

			if @users[client].cursor == @text.length
				return cb('only one longpoll') if @users[client].longpoll 
				
				@users[client].longpoll = cb
			else				
				v = @users[client]
				buffer = @text.slice(v.cursor)								
				v.cursor = @text.length
				cb null, buffer
	
	config = 
		name : 'chat'
		user_class : CellInstance

	cell.server config, ->
		console.log 'simple-chat server'.bold

	cell_client = cell.client config, ->
		console.log 'simple-chat client'.bold
	
	rpc.chat =
		open : (client,cell,cb) ->			
			cell_client.cell(cell).join(client,cb)

		__expand__ : (client) ->
			client.chats
