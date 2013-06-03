{Vector} = require './vector'
{Map,CHUNK_SIZE_MASK} = require './map'
physics = require './physics'

gravity = new Vector 0,0.25 # carefully selected to keep mantissa happy (log 2)

class Entity
	constructor : (@map,@id,pos,vel) ->			
		@pos = new Vector pos
		@vel = new Vector vel
		@flying = true

	is_flying : ->
		@flying

	tick : (deltaTick) ->				
		dirty = false		

		if @is_flying() or @vel.y
			#console.log deltaTick, @vel, @vel.mad deltaTick, gravity
			@vel = @vel.mad deltaTick, gravity

		# curPos can occupy several blocks max upto 2^dim
		# newPos also occupied upto 2^dim

		c = (x,y) => @map.get_block_type(x,y) != 0

		is_solid = (p) => @map.get_block_type(p.x,p.y) != 0

		if @vel.x 
			console.log @vel, @pos

		while @vel.size() > 0
			newPos = @pos.mad deltaTick, @vel
			altered = physics.sweep @pos, newPos, is_solid

			if altered
				if altered.x != newPos.x
					@vel.x = 0
				if altered.y != newPos.y
					@vel.y = 0

				dirty = true
				@pos = altered
			else
				@pos = newPos
				break
		
		dirty or @flying or @vel.size()

	jump : (power) ->		
		unless @is_flying()			
			@flying = true
			@vel.y = -power


module.exports.Entity = Entity
