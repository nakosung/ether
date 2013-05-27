_ = require 'underscore'
async = require 'async'

expect = (error,cb,args...) ->
	(err,result...) ->		
		if err
			cb(err)
		else if JSON.stringify(args) == JSON.stringify(result)
			cb()
		else
			cb(err)

module.exports = (server) ->
	# only auth. users can access to rooms :)
	server.use 'accounts'

	{db,rpc,deps} = server

	rooms = db.collection 'rooms'

	server.publish 'rooms', (client,cb) -> rooms.findAll({},cb)
	server.publish 'myroom', (client,cb) ->				
		deps.read client
		if client.room
			rooms.findOne {_id:client.room}, (err,doc) -> cb(err,[doc])
		else
			cb(null,[])

	# cleanup
	rooms.remove {}		

	joined = (client,room,cb) ->
		throw new Error('function req') unless _.isFunction(cb)

		auth = client.auth

		client.room = room
		deps.write client

		fn = ->		
			client.room = undefined
			deps.write client				

			async.series [
				(cb) -> rooms.update {_id:room,users:auth}, {$pull:{users:auth},$inc:{tickets:1}}, expect("couldn't join",cb,1)
				(cb) -> rooms.remove {_id:room,users:[]}, cb			
			], -> 

		
		async.series [
			(cb) -> client.acquireToken (client.tokenAlias 'room', 'room:' + auth), fn, cb
			(cb) -> client.tokenDeps (client.tokenAlias 'room'), (client.tokenAlias 'auth'), cb
		], cb

	becameOwner = (client, cb) ->
		g = client.room
		auth = client.auth

		client.is_owner = true		
		deps.write client

		fn = (taker) ->	
			client.is_owner = undefined
			deps.write client

			rooms.update {_id:g}, {$unset:{owner:1}}, -> 
		
		async.series [
			(cb) -> client.acquireToken (client.tokenAlias 'room_owner', 'room_owner:' + g), fn, cb
			(cb) -> client.tokenDeps (client.tokenAlias 'room_owner'), (client.tokenAlias 'room'), cb
		], cb		

	rpc.auth.room =
		in :
			__check__ : (client) -> client.room?

			owner : 
				__check__ : (client) -> client.is_owner

				kick : (client,opp,cb) ->					
					return cb("can't kick yourself") if String(opp) == String(client.auth)
					server.destroyToken 'room:' + db.ObjectId(opp), cb
			
			leave : (client,cb) -> 
				server.destroyToken (client.tokenAlias 'room'), cb				

			claimOwner : (client,cb) ->
				g = client.room
				auth = client.auth
				async.series [
					(cb) -> rooms.update {_id:g,users:auth,owner:null}, {$set:owner:auth}, expect('claim failed',cb,1)
					(cb) -> becameOwner client, cb
				], cb
		out :
			__check__ : (client) -> not client.room?

			create : (client,opt,cb) -> 
				auth = client.auth				
				doc = _.extend (_.extend {tickets:16}, opt), 
					owner : auth
					users : [auth]					

				# owner takes one seat
				return cb('invalid tickets') if --doc.tickets < 0

				async.waterfall [
					(cb) -> rooms.save doc, cb
					(doc,cb) -> joined client, doc._id, cb
					(a...,cb) -> becameOwner client, cb
				], cb				

			join : (client,g,cb) -> 
				g = db.ObjectId(g)

				async.series [
					(cb) -> server.destroyToken (client.tokenAlias 'room'), cb
					(cb) -> rooms.update {_id:g,tickets:$gt:0}, {$push:{users:client.auth},$inc:tickets:-1}, expect('no vacancy or invalid req',cb,1)
					(cb) -> joined client, g, cb
				], cb
