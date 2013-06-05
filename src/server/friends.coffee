# This is not a core module

_ = require 'underscore'
async = require 'async'

module.exports = (server) ->
	server.use 'rsvp'
	server.use 'accounts'

	{db,rpc} = server

	RSVP = server.rsvp

	users = db.collection 'users'

	RSVP.add_processor
		validate : (doc,cb) ->
			return cb() unless doc.what == 'hello'
			return cb('only user can say hello') unless doc.issuer.db == 'users' and doc.issuee.db == 'users' 

			users.findOne {_id:doc.issuer.id,friends:$elemMatch:id:doc.issuee.id}, db.expect('already you are friends',cb,null)

		reply : (doc,action,cb) ->
			return cb() unless doc.what == 'hello'

			issuer_db = db[doc.issuer.db]
			issuee_db = db[doc.issuee.db]
			
			switch action
				when "accept"
					async.parallel [
						(cb) -> issuer_db.update {_id:doc.issuer.id},{$push:friends:doc.issuee}, cb
						(cb) -> issuee_db.update {_id:doc.issuee.id},{$push:friends:doc.issuer}, cb
					], cb
				else 
					cb()
	
	username_or_id = (main,other,cb) ->
		flow = (q) ->
			async.waterfall [
				(cb) -> users.findOne q, cb
				(doc,cb) -> 
					return cb('invalid user') unless doc
					cb(null,doc?._id)
				main
			], cb

		try
			flow {_id:db.ObjectId(other)}
		catch e
			flow {name:other}
		
	rpc.rsvp =
		__check__ : (client) -> rpc.auth.__check__(client)

		# issue a rsvp to invite as a friend
		issue : (client,other,what,cb) ->
			@assert_fn cb
			main = (other,cb) ->
				async.waterfall [
					(cb) -> db.users.findOne {_id:other}, cb
					(doc,args...,cb) -> 
						return cb('invalid') unless doc
						RSVP.issue {db:'users',id:client.auth,name:client.name}, {db:'users',id:other,name:doc.name}, what, cb
				], cb				
			username_or_id main, other, cb

		reply : (client,rsvp,action,cb) ->
			@assert_fn cb
			RSVP.reply {db:'users',id:client.auth},rsvp,action,cb

		cancel : (client,rsvp,cb) ->
			@assert_fn cb
			RSVP.cancel {db:'users',id:client.auth},rsvp,cb

		removeFriend : (client,other,cb) ->
			@assert_fn cb
			auth = client.auth
			console.log 'remove friend', auth, other
			main = (other,cb) ->
				async.parallel [
					(cb) -> users.update {_id:auth}, {$pull:friends:id:other}, cb
					(cb) -> users.update {_id:other}, {$pull:friends:id:auth}, cb
				], cb
			username_or_id main, other, cb