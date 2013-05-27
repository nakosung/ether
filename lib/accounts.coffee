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

	connected = (client,auth,cb) ->
		client.auth = auth
		server.deps.write client

		fn = ->
			client.emit 'logout'
			client.auth = undefined
			server.deps.write client

			users.update {_id:auth,online:String(client)}, {$unset:online:1}, ->

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
				(doc,args...,cb) -> connected client, doc._id, cb
			], cb
	
	server.publish 'users:online', (client,cb) -> users.findAll({online:$ne:null},cb)	
	server.publish 'users:self', (client,cb) -> 
		server.deps.read client
		users.findOne {_id:client.auth,online:String(client)}, (err,doc) -> cb(err,[doc])			

	server.on 'client:data', (client,data) =>		
		if client.auth?
			users.update {_id:client.auth}, {$set:heartbeat:Date.now()}

	setInterval (->		
		users.update {online:{$ne:null},heartbeat:{$lt:Date.now() - HEARTBEAT_TTL}}, {$unset:online:1}
		), HEARTBEAT_TTL 