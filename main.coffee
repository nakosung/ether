ether = require './lib/ether'
_ = require 'underscore'
async = require 'async'

plugins = 'coffee-script cluster mongodb rpc stats accounts'.split(' ')	
opts = 
	cluster : false
	mongodb: ['ether',[]]

server = ether(plugins,opts)

if server
	{db,rpc} = server		
	
	mycol = db.collection 'mycollection'	

	server.publish 'test', (client,cb) -> mycol.findAll({},cb)	
	rpc.auth.addItem = (client,cb) -> mycol.save {hello:'world'}, cb
	rpc.auth.deleteItem = (client,id,cb) -> mycol.remove {_id:db.ObjectId(id)},cb
	rpc.auth.likeItem = (client,id,cb) -> mycol.update {_id:db.ObjectId(id)},$inc:like:1, cb

	rooms = db.collection 'rooms'

	server.publish 'rooms', (client,cb) -> rooms.findAll({},cb)

	# cleanup
	rooms.remove {}

	server.publish 'myroom', (client,cb) ->
		server.deps.read client
		if client.room?			
			rooms.findAll {_id:client.room,users:client.auth}, (err,docs) ->								
				if docs.length == 0										
					rpc.auth.room.leaveRoom.call rpc, client, ->
				cb(err,docs)
		else
			cb(null,[])

	server.on 'client:join', (client) ->
		client.on 'logout', ->						
			if client.room?				
				rpc.auth.room.leaveRoom.call rpc, client, ->

	rpc.auth.room = __check__ : (client) -> client.room?
	rpc.auth.room.owner = __check__ : (client) -> client.room_owner
	rpc.auth.room.owner.kick = (client,opp,cb) ->				
		rooms.update {_id:client.room,owner:client.auth}, {$pull:users:db.ObjectId(opp)}, (err,result) ->			
			cb(err,result)
	rpc.auth.no_room = __check__ : (client) -> not client.room?
	rpc.auth.no_room.createRoom = (client,opt,cb) ->		
		@assert_fn cb
		doc = title:'unnamed'		
		_.extend doc, opt		
		doc.owner = client.auth
		doc.users = [client.auth]
		rooms.save doc, (err,doc) ->			
			return cb(err) if err			
			client.room = doc._id
			client.room_owner = true
			server.deps.write client
			cb()
	rpc.auth.no_room.joinRoom = (client,room,cb) ->		
		@assert_fn cb
		room = db.ObjectId(room)
		rooms.update {_id:room}, {$push:{users:client.auth}}, (err,result) ->
			return cb(err) if err			
			if result == 1
				client.room = room
				server.deps.write client
				cb()
			else
				cb('not found')
	rpc.auth.room.leaveRoom = (client,cb) ->
		@assert_fn cb
		room = client.room
		client.room = undefined
		server.deps.write client		
		async.series [
			(cb) -> rooms.update {_id:room}, {$pull:users:client.auth}, cb
			(cb) -> rooms.remove {_id:room,users:[]}, cb
		], cb

	server.listen()