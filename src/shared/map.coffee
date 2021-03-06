{Buffer} = require 'buffer'
events = require 'events'
_ = require 'underscore'

CHUNK_SIZE_BIT = 4
CHUNK_SIZE = 1 << CHUNK_SIZE_BIT
CHUNK_SIZE_MASK = CHUNK_SIZE - 1

class Chunk extends events.EventEmitter
	constructor : (@key,@X,@Y) ->		
		@buffer = new Buffer( CHUNK_SIZE * CHUNK_SIZE * 1 )			

	toString : ->
		@key

	set_block_type : (x,y,c) ->		
		@buffer[x + (y << CHUNK_SIZE_BIT)] = c & 0xff		
		@emit 'changed','block_type',x,y,c

	get_block_type : (x,y) ->				
		@buffer[x + (y << CHUNK_SIZE_BIT)]

	set_block_meta : (x,y,c) ->
		index = (x + (y << CHUNK_SIZE_BIT)) >> 1
		if x & 1
			@buffer[index] = @buffer[index] & 0xf | (c << 4)
		else
			@buffer[index] = @buffer[index] & 0xf0 | (c & 0xf)
		@emit 'changed','block_meta',x,y,c
		
	get_block_meta : (x,y) ->
		index = (x + (y << CHUNK_SIZE_BIT)) >> 1
		if x & 1
			@buffer[index] >> 4
		else
			@buffer[index] & 0xf

	destroy : ->
		@emit 'destroy'
		@removeAllListeners()

cut = (n) ->
	int = Math.floor(n)
	frac = n - int
	[int,frac]

class Map 
	constructor : ->
		@chunks = {}
		
	chunk_key : (X,Y) -> [X.toString(36),Y.toString(36)].join(':')
	parse_key : (key) -> key.split(':').map (x) -> parseInt(x,36)

	get_chunk_abs : (x,y,cb = null) ->
		X = x >> CHUNK_SIZE_BIT
		Y = y >> CHUNK_SIZE_BIT

		@get_chunk X,Y,cb

	create_chunk : (key,X,Y) -> new Chunk(key,X,Y)
	delete_chunk : (key_or_chunk) ->
		if key_or_chunk instanceof Chunk
			chunk = key_or_chunk
			{key} = chunk
			chunk.destroy()
			delete @chunks[key]
		else
			key = key_or_chunk
			chunk = @chunks[key]
			assert(chunk?,"invalid_chunk_key")
			chunk.destroy()
			delete @chunks[key]

	get_chunk : (X,Y,cb = null) ->
		key = @chunk_key(X,Y)	
		chunk = @chunks[key]

		if chunk
			if chunk.pending?
				if cb?
					chunk.pending.push cb
				else
					null
			else
				if cb?
					cb null, chunk
				else
					chunk
		else if cb
			chunk =  @chunks[key] = @create_chunk(key,X,Y)
			chunk.pending = [cb]			
			@generate chunk,(err) =>
				cbs = chunk.pending
				delete chunk.pending
				for fn in cbs
					fn(err,chunk)
			null

	is_empty : (pos) ->		
		{x,y} = pos		
		throw new Error("WHAT" + JSON.stringify pos) unless _.isNumber(x) and _.isNumber(y)
		y = cut y
		if y[1] > 0
			@is_empty({x:x,y:y[0]}) and @is_empty({x:x,y:y[0]+1})
		else			
			x = cut x
			if x[1] > 0
				@is_empty({x:x[0],y:y[0]}) and @is_empty({x:x[0]+1,y:y[0]})
			else
				x = x[0]
				y = y[0]				
				@get_block_type(x,y) == 0
	
	get_block_type : (x,y) ->
		subx = x & CHUNK_SIZE_MASK
		suby = y & CHUNK_SIZE_MASK				
		chunk = @get_chunk_abs x,y
		chunk?.get_block_type(subx,suby) 
		
	generate : (chunk,cb) ->
		throw new Error('Not implemented')

module.exports.Map = Map
module.exports.Chunk = Chunk
module.exports.CHUNK_SIZE = CHUNK_SIZE
module.exports.CHUNK_SIZE_BIT = CHUNK_SIZE_BIT
module.exports.CHUNK_SIZE_MASK = CHUNK_SIZE_MASK