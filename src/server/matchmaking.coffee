_ = require 'underscore'
trueskill = require 'trueskill'
async = require 'async'

INITIAL_MU = 25.0
INITIAL_SIGMA = 25.0 / 3

trueskill.SetInitialMu INITIAL_MU
trueskill.SetInitialSigma INITIAL_SIGMA

module.exports = (server) ->
	server.use 'accounts'		
	server.use 'redis'

	# using redis for Z-collection
	rc = server.redis.pub

	{rpc,deps,db} = server

	col = db.collection 'mm'	

	stats = numPlayers:0	

	mm_setup = (team,cb) ->		
		console.log 'mm_setup',team

		room = null

		updateSkills = (users,cb) ->
			async.waterfall [
				# grab skills
				(cb) -> 
					jobs = users.map (u) -> (cb) -> col.findOne {_id:u.id}, cb
					async.parallel jobs, cb
				# update!
				(r,cb) ->
					v.rank = i+1 for v,i in r

					# it may consume some time... 
					trueskill.AdjustPlayers r					

					jobs = r.map (s) -> (cb) -> 
						async.series [
							(cb) -> col.update {_id:s._id}, {$set:skill:s.skill}, db.expect('skill update failed',cb,1)
							(cb) -> 
								deps.write 'skill', s._id
								cb()
						], cb						

					async.parallel jobs, cb				
			], cb

		repl = (cmd,cb) ->
			switch cmd 
				when "mm"
					async.waterfall [
						(cb) -> db.rooms.findOne {_id:room}, cb
						(doc,cb) ->
							users = _.sortBy doc.users, (x) -> x.name							
							updateSkills(users,cb)
					], cb
				else cb('unknown command')

		listener = (channel,message) ->
			console.log 'listener', message
			if message.destroyed?				
				server.destroyToken 'room:'+room, ->			
			if message.chat?[0] == '/'
				repl message.chat.substr(1), (err) ->
					console.error err if err


		fn = (taker,cb) ->
			console.log '[matchmaking]'.green.bold,'room destroyed'
			cb()		

		async.waterfall [
			(cb) -> server.createRoom {title:'Match making rulez!',private:true}, cb
			(r,cb) -> 				
				room = r
				console.log room
				server.sub 'room:'+room, listener
				server.acquireToken 'mm', 'room:'+room, fn, cb			
			(cb) ->				
				console.log 'room created', room
				jobs = team.map (x) -> (cb) -> server.acquireToken 'room:'+room, 'mm:'+x, ((args...,cb) -> cb()) , cb
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

	watch = null
	mm_end = (taker,cb) ->
		# Ooops. we got timed-out.
		if taker == "TIMEOUT"
			watch.destroy()
			cb()
		# In normal situations, we are never giving up!
		else
			cb('No way, it is mine')

	server.acquireToken server.id, 'mm:watch', mm_end, (err) ->
		unless err
			console.log 'matchmaking sits on this node'.green.bold, server.id		
			watch = deps.watch _.debounce(mm_watch,500), ['mm']

	server.publish 'mm', (client) ->
		deps.read client
		me:client.mm

	server.publish 'mm:stats', (client) ->		
		deps.read 'mm'				
		stats							

	mm_start = (client,cb) ->
		client.mm = 
			processing : true
			score : '?'		

		fn = (taker,cb) ->
			console.log 'mm_start'.red.bold, client.id, taker
			delete client.mm
			deps.write client

			async.parallel [
				(cb) -> rc.zrem 'mu', client.auth, cb
				(cb) -> rc.zrem 'sigma', client.auth, cb
				(cb) -> rc.decr 'cand', (err,result) ->
						unless err
							stats.numPlayers = result 
							deps.write 'mm'
						cb(err,result)
				(cb) ->
					# if my mm token is taken by the system? YEAH! we gonna move in!
					m = /^room:(.*)/.exec taker
					if m
						rpc.room.out.join.call rpc,client,m[1],cb						
					# the token is just removed.
					else
						cb()
			], cb			

		doc = null

		async.waterfall [			
			(cb) -> 				
				async.series [
					(cb) -> client.acquireToken (client.tokenAlias 'mm', 'mm:' + client.auth), fn, cb
					(cb) -> client.tokenDeps (client.tokenAlias 'mm'), (client.tokenAlias 'auth'), cb
				], cb		
			(args...,cb) -> 				
				col.findOne {_id:client.auth}, (err,doc) ->
					return cb(err) if err
					return cb(null,doc) if doc 
					doc = {_id:client.auth,skill:[INITIAL_MU,INITIAL_SIGMA]}
					col.save doc, (err) ->
						return cb(err) if err
						cb(null,doc)
			(doc,cb) ->								
				client.mm.skill = doc.skill				
				deps.write client

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
		start : rpc.wrap ((client) -> not client.mm?), (client,cb) ->
			async.series [				
				(cb) -> server.destroyToken (client.tokenAlias 'mm'), cb				
				(cb) -> mm_start client, cb				
			], cb			
		stop : rpc.wrap ((client) -> client.mm?), (client,cb) ->
			server.destroyToken (client.tokenAlias 'mm'), cb

	init : (cb) -> 
		rc.del 'mu', 'sigma', 'cand', cb