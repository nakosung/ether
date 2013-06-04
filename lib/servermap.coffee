async = require 'async'
_ = require 'underscore'
{Map,CHUNK_SIZE_MASK,CHUNK_SIZE} = require './shared/map'

class ChunkView
	constructor : (@map,@delta) ->
		@chunks = {}

	sub : (key,cb) ->			
		# console.log 'sub_chunk',key
		return cb('already subed') if @chunks[key]

		@chunks[key] = null

		fn = (args...) => @delta key, args				

		[X,Y] = @map.parse_key key

		async.waterfall [
			(cb) => @map.get_chunk X,Y,cb
			(chunk,cb) =>
				@chunks[key] = => 
					chunk.unsub()
					chunk.removeListener 'changed', fn
				chunk.sub()
				chunk.on 'changed', fn
				cb null,chunk.buffer.toJSON()
		], cb

	unsub : (key,cb) ->
		# console.log 'unsub_chunk',key
		if @chunks[key]
			@chunks[key]()
			delete @chunks[key]
			cb()
		else
			cb('not subed')

	unsubAll : ->
		for k,v of @chunks
			v?()

		@chunks = {}			

	destroy : ->
		@unsubAll()

class ServerMap extends Map
	constructor : (@opts) ->
		super

	createView : (delta) ->		
		new ChunkView(@,delta)
		
	generate : (chunk,cb) ->
		init = (cb) =>
			## AUTO CHECK-IN
			fn = =>					
				async.series [
					(cb) => @opts.save chunk, cb
					(cb) => if chunk.numSubs == 0
						#console.log 'drop off chunk', chunk.key
						chunk.destroy()
						delete @chunks[chunk.key]
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