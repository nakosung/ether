async = require 'async'
{Vector} = require './shared/vector'
{Entity} = require './shared/entity'
{CHUNK_SIZE_MASK,CHUNK_SIZE} = require './shared/map'
{ServerMap} = require './servermap'
events = require 'events'
_ = require 'underscore'

module.exports = (server,opts) ->
	server.use 'accounts'
	server.use 'mongodb'

	delay_save_chunk = opts?.delay_save_chunk or 5000
	delay_cold_chunk = opts?.delay_cold_chunk or 5000
	world_shutdown_delay = opts?.world_shutdown_delay or 60000

	{rpc,deps,db} = server

	world = null	

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
		constructor : ->
			opts = delay_cold_chunk : delay_cold_chunk			
			_.extend opts, chunk_mongodb()
				
			@map = new ServerMap opts
			@tickTargets = []
			@avatars = []
			@players = []	
			world = @
			@interval = setInterval (=> @tick()), 1000 / config.framerate

			fn = =>
				if @avatars.length == 0
					console.log 'shutting down world'
					@destroy()

			@on 'noplayer', _.debounce(fn,world_shutdown_delay)

		createAvatar : (client,cb) ->
			avatar = new Avatar(@,client)
			@avatars.push avatar
			avatar.init()
			cb null, avatar

		destroyAvatar : (avatar,cb) ->			
			if avatar.active
				@tickTargets.splice @tickTargets.indexOf avatar, 1
			@avatars.splice @avatars.indexOf avatar, 1
			if @avatars.length == 0
				@emit 'noplayer'
			cb()

		touch : (e) ->
			unless e.active
				@tickTargets.push e
				e.active = true

		tick : ->
			try				
				d = []
				@tickTargets.forEach (a) => 
					if a.tick()
						d.push a
					else
						a.active = false
				@tickTargets = d

				# TODO : implement 'true' view
				@avatars.forEach (a) =>
					d.forEach (other) =>
						if other != a
							a.see other
			catch e 
				console.log "WORLD",e.error
				

		destroy : ->
			clearInterval(@interval)
			world = null

	allocate_world = (client,cb) ->
		unless world
			world = new World()
			
		cb(null,world)	


	class Avatar extends Entity
		constructor : (@world,@client) ->			
			super @world.map, client.id, new Vector Math.floor(Math.random() * 100), Math.floor(Math.random() * 10)

			@age = 0
			@id = client.id

			@chunk_view = @world.map.createView (key,args) => 
				@send chunk_changed:
					key:key					
					args:args

		init : ->
			@world.players.forEach (p) =>
				@send add: id:p.id, pos:p.pos, age:p.age
				p.send add: id:@id, pos:@pos, age:@age

			@world.players.push(@)
			@send spawn:id:@id,pos:@pos			
			@world.touch(@)			

		destroy : (cb) ->
			@chunk_view.destroy()

			@world.players.forEach (p) =>
				return if p == @
				p.send remove:id:@id

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
						@see @
						cb()
				], cb
			else
				cb('invalid')

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
						@see @
						cb()
				], cb
			else
				cb('invalid')

		tick : ->
			r = super 1
			@age += 1
			r

		send : (json) -> @client.send world:json

		see : (other) ->
			@send update: id:other.id, pos:other.pos, vel:other.vel, age:other.age

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
				console.log 'adjust pos', @pos,pos,error, upper_bound
				@send update: id:@id,pos:@pos,age:@age,flying:@flying

			# if player's new suggestion is valid, use it
			else unless @pos.equals claim
				@world.touch(@)
				@pos = claim

		# vel : Object{x,y}
		updateClientVel : (vel) ->
			# if velocity hasn't been changed, skip it!
			if not @vel.equals vel
				# is player jumping?
				if vel.y < 0
					# mark we are flying
					@flying = true
					@vel.y = Math.min(@vel.y,vel.y)
				# horizontal velocity :)
				@vel.x = vel.x
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
				avatar = client.avatar
				if avatar
					delete client.avatar
					avatar.destroy(cb)

					console.log 'left'
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
					(world,cb) -> world.createAvatar client, cb
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
				if client.avatar?.chunk_view?
					client.avatar.chunk_view.sub(key,cb)
				else
					cb('no avatar')

			unsub : (client,key,cb) ->
				if client.avatar?.chunk_view?
					client.avatar.chunk_view.unsub(key,cb)
				else
					cb('no avatar')

		actions :
			__check__ : (client) -> client.avatar?
			put : (client,dir,type,cb) ->
				client.avatar.put dir, type, cb
			dig : (client,dir,cb) ->
				client.avatar.dig dir, cb
				
		update : (client,p,cb) ->
			return cb('invalid state') unless client.avatar?
			client.avatar.updateClientData(p,cb)

		leave : (client,cb) ->
			client.destroyToken 'avatar:'+client.auth, cb