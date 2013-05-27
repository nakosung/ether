_ = require 'underscore'
async = require 'async'

module.exports = (server) ->
	server.use 'accounts'
	
	{db,deps,rpc} = server

	col = db.collection 'rsvp'
	users = db.collection 'users'

	username_or_id = (main,other,cb) ->
		flow = (q) ->
			async.waterfall [
				(cb) -> users.findOne q, cb
				(doc,args...,cb) -> 
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
		issue : (client,other,what,cb) ->
			@assert_fn cb
			main = (other,cb) ->
				doc = 
					issuer : client.auth
					issuee : other
					what : what
					when : Date.now()
				
				async.waterfall [
					(cb) -> col.save doc, cb
					(doc,args...,cb) ->
						return cb('rsvp creation err') unless doc
						async.parallel [
							(cb) -> users.update {_id:client.auth}, {$push:rsvp_issued:doc._id}, cb
							(cb) -> users.update {_id:doc.issuee}, {$push:rsvp_have:doc._id}, cb
						], cb
				], cb
			username_or_id main, other, cb

			
					

