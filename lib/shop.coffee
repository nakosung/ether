# this module sells!
async = require 'async'
_ = require 'underscore'

INITIAL_MONEY = 10000

module.exports = (server) ->
	server.use 'rpc'
	server.use 'deps'	
	server.use 'accounts'

	{db,deps,rpc} = server

	skus = db.collection 'sku'		

	trade = (buyer,program,cb) ->
		return cb('invalid program') unless program?.query? and program?.update?

		buyer_db = db[buyer.db]
		return cb('invalid buyer') unless buyer_db? and buyer.id?

		q = _.extend {}, program.query
		q._id = buyer.id
		console.log q, program.update
		buyer_db.update q, program.update, db.expect('condition not met',cb,1)

	server.publishDocs 'sku', (client,cb) ->
		deps.read 'debug'
		skus.findAll {}, {program:false}, cb

	program = 		
		buy : (doc) ->
			price = parseFloat(doc.price) or 0
			query :
				money : $gte : price
				items : $not : $elemMatch : sku : doc._id
			update :
				$push : items : 
					id : doc._id
					sku : doc._id
					purchased : Date.now()
					seller : server.id
				$inc : money : -price
		refund : (doc,item) ->
			price = parseFloat(doc.price) or 0
			query :
				items:$elemMatch:id:item
			update :
				$inc:money:price
				$pull:items:id:item

	# everybody should have some money!
	server.on 'client:join', (client) ->
		client.on 'login', ->
			db.users.update {_id:client.auth,money:$not:$exists:true}, {$set:money:INITIAL_MONEY}, ->

	rpc.shop =
		__check__ : rpc.auth.__check__

		# shop keeper cannot delete sku
		keeper :
			__check__ : (client) -> true

			add : (client,doc,cb) ->
				@assert_fn cb
				skus.save doc, db.expectNot('invalid doc',cb,null)

			update : (client,sku,doc,cb) ->
				@assert_fn cb
				doc._id = db.ObjectId(doc._id)
				skus.save doc, db.expect('invalid sku',cb,1)			

		charge : (client,amount,cb) ->
			db.users.update {_id:client.auth}, {$inc:money:amount}, db.expect('failed',cb,1)

		buy : (client,sku_id,cb) ->
			@assert_fn cb
			sku_id = db.ObjectId(sku_id)
			async.waterfall [
				(cb) -> skus.findOne sku_id, db.expectNot('invalid sku',cb,null)
				(doc,cb) -> 
					p = program.buy(doc)
					return cb('sold out') if doc.soldout					
					return cb('unbuyable') unless p
					trade {db:'users', id:client.auth}, p, cb
			], cb

		refund : (client,item,cb) ->
			@assert_fn cb
			item = db.ObjectId(item)
			async.waterfall [
				(cb) -> db.users.findOne {_id:client.auth,items:$elemMatch:id:item}, db.expectNot('invalid item',cb,null)
				(doc,cb) ->
					i = null
					doc.items.forEach (ii) ->
						return unless ii.id.equals(item)
						i = ii
					return cb('internal error') unless i
					cb(null,i)
				(item,cb) -> 
					console.log item
					skus.findOne {_id:db.ObjectId(item.sku)}, db.expectNot('invalid sku',cb,null)
				(doc,cb) ->					
					p = program.refund(doc,item)
					return cb('not refundable') unless p										
					trade {db:'users', id:client.auth}, p, cb
			], cb

	init : (cb) ->
		skus.ensureIndex {name:1}, {unique:true,dropDups:true}, cb