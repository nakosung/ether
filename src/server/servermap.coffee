async = require 'async'
_ = require 'underscore'
{Map,Chunk,CHUNK_SIZE_MASK,CHUNK_SIZE} = require '../shared/map'

class ChunkView
	constructor : (@id, @map,@delta) ->
		@chunks = {}		

	toString : ->
		@id

	sub : (key,cb) ->			
		#console.log 'sub_chunk',key
		return cb('already subed') if @chunks[key]

		@chunks[key] = null

		fn = (args...) => @delta key, args				

		[X,Y] = @map.parse_key key

		async.waterfall [
			(cb) => @map.get_chunk X,Y,cb
			(chunk,cb) =>
				@chunks[key] = 
					chunk : chunk
					unsub : => chunk.unsub fn
				chunk.sub fn
				cb null,chunk.buffer.toJSON()
		], cb

	unsub : (key,cb) ->
		#console.log 'unsub_chunk',key
		if @chunks[key]
			@chunks[key].unsub()
			delete @chunks[key]
			cb()
		else
			cb('not subed')

	unsubAll : ->
		for k,v of @chunks
			v?.unsub()

		@chunks = {}			

	destroy : ->
		@unsubAll()

class ServerChunk extends Chunk
	constructor : (@key,@X,@Y) ->
		super @key, @X, @Y

		@numSubs = 0
		@numEntities = 0
		@entities = {}

	sub : (fn) ->
		@on 'changed', fn
		@numSubs += 1

	unsub : (fn) ->
		@removeListener 'changed', fn
		@numSubs -= 1

		@check()

	# check if we can vanish silently!
	check : ->		
		if @numSubs == 0 and @numEntities == 0
			@emit 'nosub'

	join : (e) ->
		unless @entities[e.id]
			@entities[e.id] = e		
			@numEntities += 1

	leave : (e) ->
		if @entities[e.id]
			delete @entities[e.id]
			@numEntities -= 1
			@check()

class ServerMap extends Map
	constructor : (@opts) ->
		super

	createView : (id,delta) ->		
		new ChunkView(id,@,delta)

	create_chunk : (key,X,Y) ->
		new ServerChunk(key,X,Y)

	generate : (chunk,cb) ->
		init = (cb) =>
			## AUTO CHECK-IN
			fn = =>					
				async.series [
					(cb) => @opts.save chunk, cb
					(cb) => if chunk.numSubs == 0
						@delete_chunk(chunk)
				], ->					

			fn = _.debounce(fn,@opts.delay_cold_chunk)
			chunk.on 'nosub', fn

			cb()

		@opts.load chunk, (err) =>			
			unless err
				init(cb)
			else if err == 'new'
				for y in [0..(CHUNK_SIZE-1)]
					for x in [0..(CHUNK_SIZE-1)]

						xx = x + (chunk.X * CHUNK_SIZE)
						yy = y + (chunk.Y * CHUNK_SIZE)

						chunk.set_block_type x, y, if yy > 13 or xx == 3 and yy < 5 then 1 else 0
				init(cb)					
			else
				cb(err)

module.exports.ServerMap = ServerMap