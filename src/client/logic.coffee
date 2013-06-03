{Entity} = require '../shared/entity'
{Vector} = require '../shared/vector'
{Map,CHUNK_SIZE_MASK,CHUNK_SIZE_BIT} = require '../shared/map'

TILE_SIZE = 24

class ClientEntity extends Entity
	constructor : (args...,@age) ->
		super args...
		localAge = 0

	tick : (deltaTick) ->
		super deltaTick			
		@sprite?.xy (@pos.x - @map.x) * TILE_SIZE, (@pos.y - @map.y) * TILE_SIZE

	record : ->
		[new Vector(@pos),new Vector(@vel)]			

	playback : (saved) ->
		@pos.set saved[0]
		@vel.set saved[1]

	simulate : (elapsedTick) ->
		saved = @record()

		@tick(elapsedTick)

		@playback saved

class ClientMap extends Map
	constructor : (@pg,@opts) ->
		super

		@view = 
			width : Math.floor @opts.width / TILE_SIZE
			height : Math.floor @opts.height / TILE_SIZE

		@receivedChunks = {}
		@tiles = []			

		@blocks = {}
		@blocks[0] = null
		@blocks[1] = new $.gQ.Animation imageURL:'img/24x24.gif'
		@blocks[2] = new $.gQ.Animation imageURL:'img/24x24.gif'

		for x in [0..31]
			@tiles.push [0..31].map (y) =>
				sprite_id = "map#{x}_#{y}"
				@pg.addSprite sprite_id, posx:TILE_SIZE*x,posy:TILE_SIZE*y,animation:null,geometry:$.gQ.GEOMETRY_RECTANGLE
				$("#"+sprite_id)

		@visible_chunks = []

	give_chunk : (chunk_key,buf) ->
		@receivedChunks[chunk_key] = buf

	generate : (chunk,cb) ->			
		console.log 'generate chunk', chunk.key
		buf = @receivedChunks[chunk.key]			
		chunk.on 'remotely_changed', (event,args...) =>
			console.log event
			switch event
				when 'block_type' then chunk.set_block_type args...
				when 'block_meta' then chunk.set_block_meta args...

			if _.contains(@visible_chunks,chunk)
				[x,y] = args
				xx = (chunk.X << CHUNK_SIZE_BIT) + x
				yy = (chunk.Y << CHUNK_SIZE_BIT) + y
				sx = xx - @x
				sy = yy - @y
				type = chunk.get_block_type x,y	
				console.log x,y,xx,yy,sx,sy,chunk.X,chunk.Y,@x,@y	
				@tiles[sx][sy].setAnimation @blocks[type]

		if buf				
			chunk.buffer = buf
			cb()
		else				
			rpc.world.sub_chunk chunk.key, (err,buf) ->
				return cb(err) if err					
				chunk.buffer = buf
				cb()

	set_pos : (x,y) ->
		return if @x == x and @y == y and not @needsRedraw
		@needsRedraw = false
		@visible_chunks = []
		@x = x
		@y = y

		for y in [0..31]
			for x in [0..31]
				do (x,y) =>
					xx = @x+x
					yy = @y+y
					@get_chunk_abs xx,yy, (err,chunk) =>
						unless err
							@visible_chunks.push chunk unless _.contains @visible_chunks		
							type = chunk.get_block_type xx & CHUNK_SIZE_MASK, yy & CHUNK_SIZE_MASK								
							@tiles[x][y].setAnimation @blocks[type]

	fit : (pos) ->			
		x = Math.floor(pos.x / @view.width) * @view.width
		y = Math.floor(pos.y / @view.height) * @view.height
		@set_pos x, y

module.exports.ClientEntity = ClientEntity
module.exports.ClientMap = ClientMap