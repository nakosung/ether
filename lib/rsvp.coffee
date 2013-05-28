_ = require 'underscore'
async = require 'async'

module.exports = (server) ->
	{db,deps,rpc} = server

	col = db.collection 'rsvp'

	RSVP = 
		issue : (issuer,issuee,what,cb) ->			
			issuer_db = db[issuer?.db]
			issuee_db = db[issuee?.db]

			return cb("invalid args for") unless issuer_db? and issuee_db? and issuer.id? and issuee.id?
			return cb("rsvp to yourself?") if JSON.stringify(issuer) == JSON.stringify(issuee)			
			
			doc = 
				issuer : issuer
				issuee : issuee
				what : what
				when : Date.now()								
			
			async.waterfall [
				(cb) -> issuer_db.findOne {_id:issuer.id,rsvp_issued:$elemMatch:{issuee:issuee,what:what}}, db.expect("pending rsvp",cb,null)
				(cb) -> col.save doc, cb
				(doc,args...,cb) ->
					return cb('rsvp creation err') unless doc
					async.parallel [
						(cb) -> issuer_db.update {_id:issuer.id}, {$push:rsvp_issued:{rsvp:doc._id,issuee:issuee,what:what}}, cb
						(cb) -> issuee_db.update {_id:issuee.id}, {$push:rsvp_have:{rsvp:doc._id}}, cb
					], cb
			], cb	

		reply : (issuee,rsvp,action,cb) ->
			issuee_db = db[issuee?.db]
			return cb("invalid args for") unless issuee_db? and issuee.id?

			rsvp = db.ObjectId(rsvp)						
			async.waterfall [				
				# ensure req is valid
				(cb) -> issuee_db.findOne {_id:issuee.id,rsvp_have:rsvp:rsvp}, db.expectNot("?",cb,null)

				# find rsvp from collection
				(cb) -> col.findAndModify {query:{_id:rsvp,canceled:null,replied:null}, update:{$set:replied:action}}, cb

				# main
				(doc,args...,cb) -> cb(null,doc)

				# clean up
				(doc,cb) ->		
					issuer_db = db[doc?.issuer.db]			
					unless doc and issuer_db?
						# delete it from have's anyway
						issuee_db.update {_id:issuee.id}, {$pull:{rsvp_have:rsvp:rsvp}}, -> cb('invalid rsvp') 
						return
					
					async.parallel [
						(cb) -> issuee_db.update {_id:doc.issuee.id}, {$pull:{rsvp_have:rsvp:rsvp}}, db.expect('no proper issuee',cb,1)
						(cb) -> issuer_db.update {_id:doc.issuer.id}, {$pull:{rsvp_issued:rsvp:rsvp}}, db.expect('no proper issuer',cb,1)
						(cb) -> col.remove {_id:rsvp}, db.expect('no rsvp',cb,1)
					],cb
			], cb

		cancel : (issuer,rsvp,cb) ->
			issuer_db = db[issuer?.db]
			return cb("invalid args for") unless issuer_db? and issuer.id?

			rsvp = db.ObjectId(rsvp)						
			async.waterfall [				
				# ensure req is valid
				(cb) -> issuer_db.findOne {_id:issuer.id,rsvp_issued:rsvp:rsvp}, db.expectNot("?",cb,null)

				# find rsvp from collection
				(cb) -> col.findAndModify {query:{_id:rsvp,canceled:null,replied:null}, update:{$set:canceled:true}}, cb
				
				# clean up
				(doc,args...,cb) ->					
					issuee_db = db[doc?.issuee.db]			
					unless doc and issuee_db?
						# delete it from have's anyway
						issuer_db.update {_id:issuer.id}, {$pull:{rsvp_issued:rsvp:rsvp}}, -> cb('invalid rsvp') 
						return
					
					async.parallel [
						(cb) -> issuee_db.update {_id:doc.issuee.id}, {$pull:{rsvp_have:rsvp:rsvp}}, db.expect('no proper issuee',cb,1)
						(cb) -> issuer_db.update {_id:doc.issuer.id}, {$pull:{rsvp_issued:rsvp:rsvp}}, db.expect('no proper issuer',cb,1)
						(cb) -> col.remove {_id:rsvp}, db.expect('no rsvp',cb,1)
					],cb
			], cb

	server.use 'accounts'
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
				RSVP.issue {db:'users',id:client.auth}, {db:'users',id:other}, what, cb
			username_or_id main, other, cb

		reply : (client,rsvp,action,cb) ->
			@assert_fn cb
			RSVP.reply {db:'users',id:client.auth},rsvp,action,cb

		cancel : (client,rsvp,cb) ->
			@assert_fn cb
			RSVP.cancel {db:'users',id:client.auth},rsvp,cb