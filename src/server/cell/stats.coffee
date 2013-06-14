redis = require 'redis'
async = require 'async'

module.exports = 
	server : (tissue,server) ->	
		server.use 'redis'
		pub = server.redis.pub
		id = tissue.id
		gen_id = tissue.config.id
		cluster = gen_id('cluster')
		members = [id,'cells'].join(':')		

		tissue.on 'add', (cell) =>
			c = gen_id(cell)
			async.parallel [
				(cb) -> pub.hset cluster, c, server.id, cb
				(cb) -> pub.sadd members, c, cb			
			], -> pub.publish cluster, '*'

		tissue.on 'remove', (cell) =>
			c = gen_id(cell)			
			async.parallel [
				(cb) -> pub.hdel cluster, c, cb
				(cb) -> pub.srem members, c, cb
			], -> pub.publish cluster, '*'

		async.waterfall [
			(cb) => pub.smembers members, cb
			(result,cb) ->				
				if result
					async.parallel [
						(cb) -> pub.hdel cluster, result..., cb
						(cb) -> pub.del members, cb
					], cb						
				else
					cb()
		], ->

	client : (tissue,server) ->
		server.use 'redis'
		server.use 'deps'
		server.use 'rpc'
		server.use 'token'

		server.rpc.celladmin =
			shutdown : (client,cell,cb) ->
				server.destroyToken cell, cb				

		deps = server.deps
		pub = server.redis.pub
		id = tissue.id
		gen_id = tissue.config.id
		cluster = gen_id('cluster')
		members = [id,'cells'].join(':')

		sub = redis.createClient()
		sub.subscribe cluster
		sub.on 'message', (channel,message) ->			
			deps.write cluster		

		server.publish cluster, (client,old,cb) ->
			deps.read cluster			
			async.waterfall [
				(cb) -> pub.hgetall cluster, cb
				(result,cb) -> cb null, result or {}
			], cb


