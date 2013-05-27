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

	GROUP_NAME = 'room'
	GROUP_OWNER = GROUP_NAME + '_owner'
	CLIENT_CACHE = GROUP_NAME
	pluralize = (x) -> x + "s"

	col = db.collection pluralize GROUP_NAME

	server.publishDocs (pluralize GROUP_NAME), (client,cb) -> col.findAll({},cb)
	server.publishDoc 'my' + GROUP_NAME, (client,cb) ->						
		deps.read client
		if client[CLIENT_CACHE]
			col.findOne {_id:client[CLIENT_CACHE]}, cb
		else
			cb()

	# cleanup
	col.remove {}		

	joined = (client,room,cb) ->
		throw new Error('function req') unless _.isFunction(cb)

		console.log "JOINED".red.bold

		auth = client.auth

		client[CLIENT_CACHE] = room
		deps.write client

		fn = ->		
			client[CLIENT_CACHE] = undefined
			deps.write client				

			async.series [
				(cb) -> col.update {_id:room,users:auth}, {$pull:{users:auth},$inc:{tickets:1}}, expect("couldn't join",cb,1)
				(cb) -> col.remove {_id:room,users:[]}, cb			
			], -> 

		
		async.series [
			(cb) -> client.acquireToken (client.tokenAlias GROUP_NAME, GROUP_NAME + ':' + auth), fn, cb
			(cb) -> client.tokenDeps (client.tokenAlias GROUP_NAME), (client.tokenAlias 'auth'), cb
		], cb

	becameOwner = (client, cb) ->
		g = client[CLIENT_CACHE]
		auth = client.auth

		client.is_owner = true		
		deps.write client

		fn = (taker) ->	
			client.is_owner = undefined
			deps.write client

			col.update {_id:g}, {$unset:{owner:1}}, -> 
		
		async.series [
			(cb) -> client.acquireToken (client.tokenAlias GROUP_OWNER, GROUP_OWNER + ':' + g), fn, cb
			(cb) -> client.tokenDeps (client.tokenAlias GROUP_OWNER), (client.tokenAlias GROUP_NAME), cb
		], cb		

	rpc.room =
		__check__ : (client) -> rpc.auth.__check__(client)

		in :
			__check__ : (client) -> client[CLIENT_CACHE]?

			owner : 
				__check__ : (client) -> client.is_owner

				kick : (client,opp,cb) ->					
					@assert_fn(cb)
					return cb("can't kick yourself") if String(opp) == String(client.auth)
					server.destroyToken 'room:' + db.ObjectId(opp), cb
			
			leave : (client,cb) -> 
				@assert_fn(cb)
				server.destroyToken (client.tokenAlias GROUP_NAME), cb				

			claimOwner : (client,cb) ->
				@assert_fn(cb)
				g = client[CLIENT_CACHE]
				auth = client.auth
				async.series [
					(cb) -> col.update {_id:g,users:auth,owner:null}, {$set:owner:auth}, expect('claim failed',cb,1)
					(cb) -> becameOwner client, cb
				], cb
		out :
			__check__ : (client) -> not client[CLIENT_CACHE]?

			create : (client,opt,cb) -> 
				@assert_fn(cb)
				auth = client.auth
				doc = _.extend (_.extend {tickets:16}, opt), 
					owner : auth
					users : [auth]					

				# owner takes one seat
				return cb('invalid tickets') if --doc.tickets < 0

				async.waterfall [
					(cb) -> col.save doc, cb
					(doc,cb) -> joined client, doc._id, cb
					(a...,cb) -> becameOwner client, cb
				], cb				

			join : (client,g,cb) -> 
				@assert_fn(cb)
				g = db.ObjectId(g)
				auth = client.auth

				async.series [
					(cb) -> server.destroyToken (client.tokenAlias GROUP_NAME), cb
					(cb) -> col.update {_id:g,tickets:$gt:0}, {$push:{users:auth},$inc:tickets:-1}, expect('no vacancy or invalid req',cb,1)
					(cb) -> joined client, g, cb
				], cb
