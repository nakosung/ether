# this module sells!
async = require 'async'

module.exports = (server) ->
	server.use 'rpc'
	server.use 'deps'
	server.use 'rpc'

	{db,deps,rpc} = server

	skus = db.collection 'sku'

	trade = (buyer,program,cb) ->
		return cb('invalid program') unless program?.query? and program?.update?

		buyer_db = db[buyer].db
		return cb('invalid buyer') unless buyer_db? and buyer.id?

		q = _.extend {}, program.query
		q._id = buyer.id
		buyer_db.update q, program.update, db.expect('condition not met',cb,1)

	server.publishDocs 'sku', (client,cb) ->
		deps.read 'debug'
		skus.findAll {}, {program:false}, cb

	rpc.shop =
		__check__ : rpc.auth.__check__

		# shop keeper cannot delete sku
		keeper :
			__check__ : (client) -> true

			add : (client,doc,cb) ->
				@assert_fn cb
				skus.save doc, db.expectNot('invalid doc',cb,null)

			update : (client,sku,program,cb) ->
				@assert_fn cb
				console.log sku,JSON.stringify program
				skus.update {_id:db.ObjectId(sku)}, program, db.expect('invalid sku',cb,1)

			update_simple : (client,sku,opts,cb) ->
				@assert_fn cb
				sku = db.ObjectId(sku)
				price = opts?.price or 0
				program =
					buy :
						query :
							$gte : money : price
							items : $not : $elemMatch : sku : sku
						update :
							$push : items : 
								id : sku
								sku : sku
								purchased : Date.now()
								seller : server.id
							$inc : money : -price
					refund : 
						update :
							$inc : money : price

				rpc.shop.keeper.update.call @, client, sku, $set:program:program, cb

		buy : (client,sku_id,cb) ->
			@assert_fn cb
			sku_id = db.ObjectId(sku_id)
			async.waterfall [
				(cb) -> skus.findOne sku_id, db.expectNot('invalid sku',cb,null)
				(doc,cb) -> 
					return cb('sold out') if doc.soldout
					return cb('unbuyable') unless doc.program?.buy?
					trade {db:'users', id:client.auth}, doc.program.buy, cb
			], cb

		refund : (client,item,cb) ->
			@assert_fn cb
			item = db.ObjectId(item)
			async.waterfall [
				(cb) -> db.users.findOne {_id:client.auth,items:$elemMatch:id:item}, db.expectNot('invalid item',cb,null)
				(doc,cb) ->
					i = null
					doc.items.forEach (item) ->
						return unless item.id == item
						i = item
					return cb('internal error') unless i
					cb(null,i)
				(item,cb) -> skus.findOne item.sku, db.expectNot('invalid sku',cb,null)
				(doc,cb) ->
					return cb('not refundable') unless doc.program?.refund?
					refund = _.extend {query:{},update:{}}, doc.program.refund
					_.extend refund.query, items:$elemMatch:id:item
					_.extend refund.update, $unset:'items.$':1
					trade {db:'users', id:client.auth}, refund, cb
			], cb
