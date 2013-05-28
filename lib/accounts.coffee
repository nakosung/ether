_ = require 'underscore'
async = require 'async'

HEARTBEAT_TTL = 1000 * 30 # 30 sec

module.exports = (server) ->
	server.use './rpc'
	server.use './mongodb'
	server.use 'deps'
	server.use 'token'

	db = server.db
	users = db.collection 'users'

	users.org.ensureIndex {name:1}, {unique:true,dropDups:true}	

	rpc = @rpc

	connected = (client,auth,name,cb) ->
		client.auth = auth
		client.name = name
		server.deps.write client

		fn = (taker,cb) ->
			client.emit 'logout'
			client.auth = undefined
			client.name = undefined
			server.deps.write client

			users.update {_id:auth,online:String(client)}, {$unset:online:1}, cb

		async.series [
			(cb) -> client.acquireToken (client.tokenAlias 'auth', 'user:'+auth), fn, cb			
			(cb) ->
				client.emit 'login'
				cb()
		], cb	

	rpc.auth = 
		__check__ : (client) -> client.auth?

		## LOGOUT
		logout : (client,cb) ->
			@assert_fn cb

			server.destroyToken (client.tokenAlias 'auth')					

		list : 
			users : (client,pat,cb) ->
				@assert_fn cb
				q = 					
					name:new RegExp("^#{pat}")

				users.find(q, {name:true}).limit 5, (err,result) -> 
					cb err, (result or []).map (x) -> x.name
	rpc.noauth = 
		__check__ : (client) -> not client.auth?

		## REGISTRATION
		register : (client,name,pwd,opt,cb) ->		
			@assert_fn cb

			doc = opt
			_.extend doc,
				name : name
				pwd : pwd		
			users.save doc, cb

		## LOGIN	
		login : (client,name,pwd,cb) -> 
			@assert_fn cb
			
			q = 
				query:{name:name,pwd:pwd}
				update:{$set:online:String(client),heartbeat:Date.now()}

			async.waterfall [
				(cb) -> users.findAndModify q, cb
				(doc,args...,cb) -> 
					return cb('invalid login') unless doc
					connected client, doc._id, doc.name, cb
			], cb

	server.ClientClass::tag = -> {id:@auth,name:@name}
	
	server.publishDocs 'users_online', (client,cb) -> users.findAll({online:$ne:null},{name:true},cb)
	server.publishDoc 'me', (client,cb) -> 
		server.deps.read client
		users.findOne {_id:client.auth,online:String(client)}, {pwd:false,heartbeat:false}, cb

	server.on 'client:data', (client,data) =>		
		if client.auth?
			users.update {_id:client.auth}, {$set:heartbeat:Date.now()}

	setInterval (->		
		users.update {online:{$ne:null},heartbeat:{$lt:Date.now() - HEARTBEAT_TTL}}, {$unset:online:1}
		), HEARTBEAT_TTL 