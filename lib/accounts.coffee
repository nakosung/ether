_ = require 'underscore'
async = require 'async'

HEARTBEAT_TTL = 1000 * 30 # 30 sec

module.exports = (server) ->
	server.use './rpc'
	server.use './mongodb'
	server.use 'deps'

	db = server.db
	users = db.collection 'users'

	users.org.ensureIndex {name:1}, {unique:true,dropDups:true}	

	server.ClientClass::set_auth = (auth,cb) ->
		@auth = auth
		server.deps.write @

		if auth?
			@emit 'login'
		else
			@emit 'logout' 

		cb()

	rpc = @rpc

	rpc.auth = __check__ : (client) -> client.auth?
	rpc.noauth = __check__ : (client) -> not client.auth?
	
	## REGISTRATION
	rpc.noauth.register = (client,name,pwd,opt,cb) ->		
		@assert_fn cb

		doc = opt
		_.extend doc,
			name : name
			pwd : pwd		
		users.save doc, cb

	## LOGIN	
	rpc.noauth.login = (client,name,pwd,cb) -> 
		@assert_fn cb
		
		q = 
			query:{name:name,pwd:pwd}
			update:{$set:online:String(client),heartbeat:Date.now()}

		users.findAndModify q, (err,doc) ->			
			if doc
				client.set_auth(doc._id,cb)		
			else
				cb('none')	

	## LOGOUT
	rpc.auth.logout = (client,cb) ->
		@assert_fn cb

		async.series [
			(cb) -> users.update {_id:client.auth}, {$unset:online:1}, cb
			(cb) -> client.set_auth undefined, cb
		], (err,result) ->			
			cb(err,result)			

	server.on 'client:join', (client) ->
		client.once 'close', ->						
			if client.auth?				
				rpc.auth.logout.call rpc, client, ->					

	server.publish 'users:online', (client,cb) -> users.findAll({online:$ne:null},cb)	
	server.publish 'users:self', (client,cb) -> 
		server.deps.read client
		users.findAll {_id:client.auth,online:String(client)}, (err,docs) ->		
			# connected by other peer	
			if docs.length == 0 and client.auth?				
				client.set_auth undefined, ->
					cb(err,docs)
			else
				cb(err,docs)

	server.on 'client:data', (client,data) =>
		return unless data.heartbeat?
		if client.auth?
			users.update {_id:client.auth}, {$set:heartbeat:Date.now()}

	setInterval (->		
		users.update {online:{$ne:null},heartbeat:{$lt:Date.now() - HEARTBEAT_TTL}}, {$unset:online:1}
		), HEARTBEAT_TTL 