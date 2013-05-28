_ = require 'underscore'
trueskill = require 'trueskill'
redis = require 'redis'
async = require 'async'

INITIAL_MU = 25.0
INITIAL_SIGMA = 25.0 / 3

trueskill.SetInitialMu INITIAL_MU
trueskill.SetInitialSigma INITIAL_SIGMA

module.exports = (server) ->
	server.use 'accounts'		

	rc = redis.createClient()

	rc.keys "mm:*", (err,result) ->
		console.log result
		rc.del result..., console.log

	{rpc,deps,db} = server

	col = db.collection 'mm'
	#col.remove {}

	rc.del 'mu', 'sigma', 'cand', ->

	stats = 
		numPlayers:0	

	mm_setup = (team,cb) ->		
		console.log 'mm_setup',team
		async.waterfall [
			(cb) -> server.createRoom {title:'Match making rulez!'}, cb
			(room,cb) ->				
				console.log 'room created', room
				jobs = team.map (x) -> (cb) -> server.acquireToken room, 'mm:'+x, undefined, cb
				async.parallel jobs, (err) ->
					if err
						server.destroyRoom room, cb
					else
						cb()
		], cb

	mm_watch = ->				
		# TO PREVENT REENTRANCY
		return if @doing 
		@doing = true
		cb = =>	@doing = false

		N = 2
		
		async.waterfall [
			(cb) -> rc.zrange 'mu', 0, -1, cb
			(result,cb) ->
				console.log 'mm_watch', result
				jobs = []
				while result.length >= N
					team = result.splice(0,N)
					jobs.push (cb) -> mm_setup(team,cb)					
				async.parallel jobs, cb			
		], cb

	deps.watch _.debounce(mm_watch,500), ['mm']

	server.publish 'mm', (client,cb) ->		
		deps.read 'mm'
		cb null, 
			stats:stats				
			me:client.mm

	mm_start = (client,cb) ->		
		client.mm = 
			processing : true
			score : '?'

		deps.write 'mm'			

		fn = (taker,cb) ->						
			delete client.mm
			deps.write 'mm'

			async.parallel [
				(cb) -> rc.zrem 'mu', client.auth, cb
				(cb) -> rc.zrem 'sigma', client.auth, cb
				(cb) -> rc.decr 'cand', (err,result) ->
						unless err
							stats.numPlayers = result 
							deps.write 'mm'
						cb(err,result)
				(cb) ->
					return cb() unless taker

					rpc.room.out.join.call rpc,client,taker,cb
			], cb			

		doc = null

		async.waterfall [			
			(cb) -> 				
				async.series [
					(cb) -> client.acquireToken (client.tokenAlias 'mm', 'mm:' + client.auth), fn, cb
					(cb) -> client.tokenDeps (client.tokenAlias 'mm'), (client.tokenAlias 'auth'), cb
				], cb		
			(args...,cb) -> 				
				col.findOne {_id:client.auth}, (err,r,doc) ->								
					return cb(err) if err
					return cb(null,doc) if doc 
					doc = {_id:client.auth,skill:[INITIAL_MU,INITIAL_SIGMA]}
					col.save doc, (err) ->
						return cb(err) if err
						cb(null,doc)
			(doc,cb) ->								
				client.mm.skill = doc.skill				
				deps.write 'mm'

				async.parallel [
					(cb) -> rc.zadd 'mu', doc.skill[0], client.auth, cb
					(cb) -> rc.zadd 'sigma', doc.skill[1], client.auth, cb
					(cb) -> rc.incr 'cand', (err,result) ->
						unless err
							stats.numPlayers = result 
							deps.write 'mm'
						cb(err,result)
				], cb
		], cb

	rpc.mm =
		__check__ : (client) -> rpc.auth.__check__(client)
		start : (client,cb) ->
			async.series [				
				(cb) -> server.destroyToken (client.tokenAlias 'mm'), cb				
				(cb) -> mm_start client, cb				
			], cb			
		stop : (client,cb) ->
			server.destroyToken (client.tokenAlias 'mm'), cb
