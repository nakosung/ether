async = require 'async'
{Vector} = require '../shared/vector'
{Entity} = require '../shared/entity'
{CHUNK_SIZE_MASK,CHUNK_SIZE} = require '../shared/map'
{ServerMap} = require './servermap'
events = require 'events'
_ = require 'underscore'

module.exports = (server,opts) ->
	server.use 'accounts'
	server.use 'mongodb'
	server.use 'worldview'

	delay_save_chunk = opts?.delay_save_chunk or 5000
	delay_cold_chunk = opts?.delay_cold_chunk or 5000
	world_shutdown_delay = opts?.world_shutdown_delay or 60000

	{rpc,deps,db} = server

	TheWorld = null	

	chunk_mongodb = ->
		chunk_db = db.collection 'chunk'

		save : (chunk,cb) ->
			chunk_db.save {_id:chunk.key,raw:chunk.buffer.toString()}, cb

		load : (chunk,cb) ->
			chunk_db.findOne {_id:chunk.key}, (err,doc) =>
				if err
					cb(err)
				else if doc							
					#console.log 'fetch from db', chunk.key
					chunk.buffer = new Buffer(doc.raw)
					cb(null,chunk)
				else
					cb('new')

	config = 
		allowed_latency : 1000
		framerate : 20

	class World extends events.EventEmitter
		constructor : (@id) ->
			@age = 0
			opts = delay_cold_chunk : delay_cold_chunk			
			_.extend opts, chunk_mongodb()
				
			@map = new ServerMap opts
			@tickTargets = []
			@avatars = []
			@players = []				
			@interval = setInterval (=> @tick()), 1000 / config.framerate

			fn = =>
				if @avatars.length == 0
					console.log 'shutting down world'
					@destroy()

			@on 'noplayer', _.debounce(fn,world_shutdown_delay)

		toString : -> ["TheWorld",@id].join(':')

		createAvatar : (client,cb) ->
			avatar = new Avatar(@,client)
			@avatars.push avatar
			avatar.init()
			cb null, avatar

		destroyAvatar : (avatar,cb) ->						
			if avatar.active
				@tickTargets.splice @tickTargets.indexOf(avatar), 1
			@avatars.splice @avatars.indexOf(avatar), 1						
			if @avatars.length == 0
				@emit 'noplayer'
			cb()

		touch : (e) ->
			unless e.active
				@tickTargets.push e
				e.active = true

		tick : ->
			@age += 1
			try				
				d = []
				@tickTargets.forEach (a) => 
					if a.tick()
						d.push a
					else
						a.active = false				

				@tickTargets = d
			catch e 
				console.log "WORLD",e.error

			deps.write @
				

		destroy : ->
			clearInterval(@interval)			

	world_id = 0
	allocate_world = (client,cb) ->		
		unless TheWorld			
			TheWorld = new World(world_id++)			
			
		cb(null,TheWorld)	
	
	class Avatar extends Entity
		constructor : (@world,@client) ->			
			super @world.map, client.id, new Vector Math.floor(Math.random() * 100), Math.floor(Math.random() * 10)

			@age = 0
			@id = client.id			
			@corrected = true
			@chunk = null

		migrateTo : (chunk) ->
			return if chunk == @chunk 
			@chunk.leave(@) if @chunk
			@chunk = chunk
			@chunk.join(@)

		init : ->
			@world.players.push(@)			
			@world.touch(@)			

		destroy : (cb) ->
			@chunk.leave(@) if @chunk
			@chunk = null
			@world.players.splice @world.players.indexOf(@), 1
			@world.destroyAvatar @, cb
		
		## ACTIONS
		put : (dir,type,cb) ->
			nx = Math.floor @pos.x + 0.5
			ny = Math.floor @pos.y + 0.5
			dir = new Vector dir
			tx = nx + dir.x
			ty = ny + dir.y
			if @map.get_block_type(nx,ny+1) == 0
				async.waterfall [
					(cb) => @map.get_chunk_abs tx, ty, cb
					(chunk,cb) => 
						chunk.set_block_type tx & CHUNK_SIZE_MASK, ty & CHUNK_SIZE_MASK, type
						@breakSimulation()
						cb()
				], cb
			else
				cb('invalid')

		follow : (other,cb) ->
			for a in @world.avatars
				if a.id == other
					@warpTo a.pos
					return cb()
			return cb('invalid target')

		warpTo : (pos) ->
			@pos = pos
			@vel = new Vector
			@breakSimulation('warp')

		dig : (dir,cb) ->
			nx = Math.floor @pos.x + 0.5
			ny = Math.floor @pos.y + 0.5
			dir = new Vector dir
			tx = nx + dir.x
			ty = ny + dir.y

			type = 0
			if @map.get_block_type(tx,ty) != 0
				async.waterfall [
					(cb) => @map.get_chunk_abs tx, ty, cb
					(chunk,cb) => 
						chunk.set_block_type tx & CHUNK_SIZE_MASK, ty & CHUNK_SIZE_MASK, type
						@flying = true
						@world.touch(@)
						@breakSimulation()
						cb()
				], cb
			else
				cb('invalid')

		breakSimulation : (reason) ->
			@age = @world.age
#			console.log reason			

		tick : ->
			r = super 1			

			async.waterfall [
				(cb) => @map.get_chunk_abs @pos.x,@pos.y, cb
				(chunk,cb) => 
					@migrateTo chunk
					cb()
			], ->

			r

		send : (json) -> @client.send world:json

		snapshot : (target) -> 
			if target == @client								
				if @corrected
					@corrected = false
					id:@id, pos:@pos, vel:@vel, age:@age, flying:@flying
				else
					id:@id, age:@age
			else
				id:@id, pos:@pos, vel:@vel, age:@age, flying:@flying
		
		# pos : Object{x,y}
		updateClientPos : (pos) ->
			claim = new Vector(pos)

			# error
			error = claim.sub(@pos).size()

			# allowed_latent_ticks = latency / deltaTime (= 1000/framerate)
			margin = @vel.size()

			# HUGE heuristic : HACK
			if @active
				margin += 1
			upper_bound = margin * config.allowed_latency * config.framerate / 1000

			# we need to re-position player
			if error > upper_bound				
				@corrected = true

			# if player's new suggestion is valid, use it
			else if @vel.size() == 0 and not @pos.equals claim				
				@breakSimulation('claim')
				@world.touch(@)
				@pos = claim

		# vel : Object{x,y}
		updateClientVel : (vel) ->
			# if velocity hasn't been changed, skip it!
			if @vel.x != vel.x
				@breakSimulation('vel.x')				
				# horizontal velocity :)
				@vel.x = vel.x
				# yes, we need to be ticked
				@world.touch(@)

			if @vel.y != vel.y and not @flying				
				@breakSimulation('flying')				
				# horizontal velocity :)
				@vel.y = vel.y
				@flying = vel.y < 0
				# yes, we need to be ticked
				@world.touch(@)


		# client sends pos, vel periodically only if necessary
		updateClientData : (p,cb) ->			
			# adjust client position
			@updateClientVel(p.vel) if p.vel?				

			# position update
			@updateClientPos(p.pos) if p.pos?								

			# all synchronous
			cb()

	

	rpc.world =
		__check__ : rpc.auth.__check__

		enter : (client,cb) ->
			@assert_fn cb			

			fn = (taker,cb) ->
				if client.chunk_view?
					client.chunk_view.destroy()

				avatar = client.avatar
				if avatar
					console.log 'left', client.avatar.id

					delete client.avatar
					avatar.destroy(cb)
					
					deps.write client
				else
					cb()

			token = 'avatar:'+client.auth			

			async.waterfall [
				(cb) -> async.series [
					(cb) -> client.destroyToken token, cb
					(cb) -> client.acquireToken token, fn, cb
					(cb) -> client.tokenDeps token, (client.tokenAlias 'auth'), cb				
				], cb
				(args...,cb) -> cb(null,config)
			], cb			

		hello : (client,cb) ->			
			if client.avatar?
				cb('already helloed')
			else
				async.waterfall [
					(cb) -> allocate_world client, cb
					(world,cb) -> 
						client.chunk_view = world.map.createView (key,args) => 
							client.send world:chunk_changed:{key:key,args:args}
						world.createAvatar client, cb
					(avatar,cb) -> 						
						client.avatar = avatar						
						console.log 'joined'
						deps.write client
						cb()
				], cb

		time : (client,time,cb) ->
			cb null, Date.now()

		chunk : 
			sub : (client,key,cb) ->
				if client.chunk_view?
					client.chunk_view.sub(key,cb)
				else
					cb('no avatar')

			unsub : (client,key,cb) ->
				if client.chunk_view?
					client.chunk_view.unsub(key,cb)
				else
					cb('no avatar')

		actions :
			__check__ : (client) -> client.avatar?
			put : (client,dir,type,cb) ->
				client.avatar.put dir, type, cb
			dig : (client,dir,cb) ->
				client.avatar.dig dir, cb
			follow : (client,other,cb) ->
				client.avatar.follow other, cb
				
		update : (client,p,cb) ->
			return cb('invalid state') unless client.avatar?
			client.avatar.updateClientData(p,cb)

		leave : (client,cb) ->
			client.destroyToken 'avatar:'+client.auth, cb