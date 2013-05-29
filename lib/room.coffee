_ = require 'underscore'
async = require 'async'

# this module should be remained as 'basic' so that extensions can be installed. :)
module.exports = (server) ->
	# only auth. users can access to rooms :)
	server.use 'accounts'

	{db,rpc,deps} = server

	expect = db.expect

	GROUP_NAME = 'room'
	GROUP_OWNER = GROUP_NAME + '_owner'
	CLIENT_CACHE = GROUP_NAME
	pluralize = (x) -> x + "s"

	col = db.collection pluralize GROUP_NAME

	server.publishDocs (pluralize GROUP_NAME), (client,cb) -> col.findAll {private:null},cb
	server.publishDoc 'my' + GROUP_NAME, (client,cb) ->						
		deps.read client
		if client[CLIENT_CACHE]
			col.findOne {_id:client[CLIENT_CACHE]}, cb
		else
			cb()

	# cleanup
	col.remove {}	

	channel = (room) -> [GROUP_NAME,room].join(':')

	notify = (room,message) ->
		server.pub channel(room),message	

	server.createRoom = (opt,cb) -> 				
		doc = _.extend (_.extend {tickets:16}, opt), 
			owner : "<system>"
			users : []							

		col.save doc, (err,result) ->
			return cb(err) if err
			cb(null,result._id)

	server.destroyRoom = (room,cb) ->		
		async.waterfall [
			(cb) -> 
				# mark it so that nobody can join any more!
				col.findAndModify {query:{_id:room},update:{$set:{tickets:-99999,private:true}}}, cb

			(doc,args...,cb) -> 	
				return cb('no room') unless doc

				# all users are being kicked out
				jobs = doc.users.map (x) -> (cb) -> server.destroyToken 'room:' + x.id, cb
				async.parallel jobs, cb

			# in case of 0-user room, we need to remove explicitly.
			(cb) -> col.remove {_id:room}, cb
			(args...,cb) -> 
				notify(room,destroyed:true) 
				cb()
		], cb

	joined = (client,room,cb) ->
		throw new Error('function req') unless _.isFunction(cb)		

		auth = client.auth
		tag = client.tag()

		client[CLIENT_CACHE] = room
		deps.write client
		
		relay = (channel,msg) -> client.publish channel, msg
		server.sub channel(room), relay
		notify room, joined:client.name

		fn = (taker,cb) ->		
			notify room, left:client.name
			server.unsub channel(room), relay

			client[CLIENT_CACHE] = undefined
			deps.write client				

			async.waterfall [
				(cb) -> col.update {_id:room,users:tag}, {$pull:{users:tag},$inc:{tickets:1}}, expect("couldn't join",cb,1)
				(cb) -> col.remove {_id:room,users:[]}, cb
				(result,cb) ->
					notify(room,destroyed:true) if result == 1
					cb()
			], cb

		
		async.series [
			(cb) -> client.acquireToken (client.tokenAlias GROUP_NAME, GROUP_NAME + ':' + auth), fn, cb
			(cb) -> client.tokenDeps (client.tokenAlias GROUP_NAME), (client.tokenAlias 'auth'), cb
		], cb

	becameOwner = (client, cb) ->
		g = client[CLIENT_CACHE]
		auth = client.auth

		client.is_owner = true		
		deps.write client

		fn = (taker,cb) ->	
			client.is_owner = undefined
			deps.write client

			col.update {_id:g}, {$unset:{owner:1}}, cb
		
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

			chat : (client,msg,cb) ->
				server.pub [GROUP_NAME,client[CLIENT_CACHE]].join(':'), sender:client.name, chat:msg
			
			leave : (client,cb) -> 
				@assert_fn(cb)
				server.destroyToken (client.tokenAlias GROUP_NAME), cb				

			claimOwner : (client,cb) ->
				@assert_fn(cb)
				g = client[CLIENT_CACHE]
				auth = client.auth
				tag = client.tag()
				async.series [
					(cb) -> col.update {_id:g,users:tag,owner:null}, {$set:owner:auth}, expect('claim failed',cb,1)
					(cb) -> becameOwner client, cb
				], cb
		out :
			__check__ : (client) -> not client[CLIENT_CACHE]?

			create : (client,opt,cb) -> 
				@assert_fn(cb)
				auth = client.auth
				tag = client.tag()
				doc = _.extend (_.extend {tickets:16}, opt), 
					owner : auth
					users : [tag]

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
				tag = client.tag()

				async.series [
					(cb) -> server.destroyToken (client.tokenAlias GROUP_NAME), cb
					(cb) -> col.update {_id:g,tickets:$gt:0}, {$push:{users:tag},$inc:tickets:-1}, expect('no vacancy or invalid req',cb,1)
					(cb) -> joined client, g, cb
				], cb
