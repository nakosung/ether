async = require 'async'
{Vector} = require './shared/vector'
{Entity} = require './shared/entity'
{Map,CHUNK_SIZE_MASK,CHUNK_SIZE} = require './shared/map'

module.exports = (server) ->
	server.use 'accounts'

	{rpc,deps} = server

	world = null	

	config = 
		allowed_latency : 1000
		framerate : 20

	class ServerMap extends Map
		generate : (chunk,cb) ->
			for y in [0..(CHUNK_SIZE-1)]
				for x in [0..(CHUNK_SIZE-1)]

					xx = x + (chunk.X * CHUNK_SIZE)
					yy = y + (chunk.Y * CHUNK_SIZE)

					chunk.set_block_type x, y, if yy > 13 or xx == 3 and yy < 5 then 1 else 0			
			cb()

	class World
		constructor : ->
			@map = new ServerMap()
			@tickTargets = []
			@avatars = []
			world = @
			@interval = setInterval (=> @tick()), 1000 / config.framerate

		createAvatar : (client,cb) ->
			avatar = new Avatar(@,client)
			@avatars.push avatar			
			cb null, avatar

		destroyAvatar : (avatar,cb) ->			
			@avatars.splice @avatars.indexOf avatar, 1
			if @avatars.length == 0
				@destroy()
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
				console.log e.error
				

		destroy : ->
			clearInterval(@interval)
			world = null

	allocate_world = (client,cb) ->
		unless world
			world = new World()
			
		cb(null,world)

	players = []

	class Avatar extends Entity
		constructor : (@world,@client) ->			
			super @world.map, client.id, new Vector Math.floor(Math.random() * 20), Math.floor(Math.random() * 20)

			@age = 0
			@id = client.id

			players.forEach (p) =>
				@send add: id:p.id, pos:p.pos, age:p.age
				p.send add: id:@id, pos:@pos, age:@age

			players.push(@)
			@send spawn:id:@id,pos:@pos
			@chunks = {}

		sub_chunk : (key,cb) ->			
			return cb('already subed') if @chunks[key]

			@chunks[key] = null

			fn = (args...) =>
				@send chunk_changed:
					key:key					
					args:args

			[X,Y] = @map.parse_key key

			async.waterfall [
				(cb) => @map.get_chunk X,Y,cb
				(chunk,cb) => 				
					@chunks[key] = => chunk.removeListener 'changed', fn
					chunk.on 'changed', fn
					cb null,chunk.buffer.toJSON()
			], cb

		unsub_chunk : (key,cb) ->
			if @chunks[key]
				@chunks[key]()
				delete @chunks[key]
				cb()
			else
				cb('not subed')

		unsubAllChunks : ->
			for k,v of @chunks
				v()

			@chunks = {}			

		put : (type,cb) ->
			if @map.is_empty @pos.x, @pos.y-1 and @map.is_empty @pos.x, @pos.y+1							
				@vel.y = 0
				tx = @pos.x
				ty = @pos.y + 1				
				async.waterfall [
					(cb) => @map.get_chunk_abs tx, ty, cb
					(chunk,cb) => chunk.set_block_type tx & CHUNK_SIZE_MASK, ty & CHUNK_SIZE_MASK, type, cb
					(cb) => @see @
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

		update : (p,cb) ->			
			@vel.set p.vel if p.vel?

			@world.touch(@)

			# adjust client position if necessary
			if p.pos?
				claim = new Vector(p.pos)
				error = claim.sub(@pos).size()				

				# allowed_latent_ticks = latency / deltaTime (= 1000/framerate)
				upper_bound = @vel.size() * config.allowed_latency * config.framerate / 1000 + 0.01

				if error > upper_bound
					console.log 'adjust pos', error, upper_bound
					@send update: id:@id,pos:@pos,age:@age			

			cb()

		destroy : (cb) ->
			@unsubAllChunks()

			players.forEach (p) =>
				return if p == @
				p.send remove:id:@id

			players.splice players.indexOf(@), 1
			@world.destroyAvatar @, cb

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

		sub_chunk : (client,key,cb) ->			
			if client.avatar?
				client.avatar.sub_chunk(key,cb)
			else
				cb('no avatar')

		unsub_chunk : (client,key,cb) ->
			if client.avatar?
				client.avatar.unsub_chunk(key,cb)
			else
				cb('no avatar')

		actions :
			__check__ : (client) -> client.avatar?
			put : (client,type,cb) ->
				client.avatar.put type, cb
				
		update : (client,p,cb) ->
			return cb('invalid state') unless client.avatar?
			client.avatar.update(p,cb)

		leave : (client,cb) ->
			client.destroyToken 'avatar:'+client.auth, cb