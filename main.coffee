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

	set = (group,collection) ->
		group_owner = group + "_owner"
		joined = 
			__check__ : (client) -> client[group]?
			owner :
				__check__ : (client) -> client[group_owner]
				kick : (client,opp,cb) ->				
					collection.update {_id:client[group],owner:client.auth}, {$pull:users:db.ObjectId(opp)}, (err,result) ->			
						cb(err,result)
			leave : (client,cb) ->
				@assert_fn cb
				g = client[group]
				client[group] = undefined
				server.deps.write client		
				async.series [
					(cb) -> collection.update {_id:g}, {$pull:users:client.auth}, cb
					(cb) -> collection.remove {_id:g,users:[]}, cb
				], cb
		not_joined = 
			__check__ : (client) -> not client[group]?
			create : (client,opt,cb) ->		
				@assert_fn cb
				doc = title:'unnamed'		
				_.extend doc, opt		
				doc.owner = client.auth
				doc.users = [client.auth]
				collection.save doc, (err,doc) ->			
					return cb(err) if err			
					client[group] = doc._id
					client[group_owner] = true
					server.deps.write client
					cb()
			join : (client,g,cb) ->		
				@assert_fn cb
				g = db.ObjectId(g)
				collection.update {_id:g}, {$push:{users:client.auth}}, (err,result) ->
					return cb(err) if err			
					if result == 1
						client[group] = g
						server.deps.write client
						cb()
					else
						cb('not found')
		o = {}
		o[group] = 
			in:joined
			out:not_joined
		o

	_.extend rpc.auth, set('room',rooms)
		
			
	server.listen()