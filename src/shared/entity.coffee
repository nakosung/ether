{Vector} = require './vector'
{Map,CHUNK_SIZE_MASK} = require './map'
physics = require './physics'

gravity = new Vector 0,0.25 # carefully selected to keep mantissa happy (log 2)
TERMINAL_VELOCITY = 0.75

class Entity
	constructor : (@map,@id,pos,vel) ->			
		@pos = new Vector pos
		@vel = new Vector vel
		@flying = true

	is_flying : ->
		@flying

	is_on_solid : ->
		i = @pos.floor()
		if i.y != @pos.y
			false
		else 
			i.y += 1
			is_solid = (p) => @map.get_block_type(p.x,p.y) != 0

			if is_solid(i) 
				true
			else
				i.x += 1
				is_solid(i)					

	tick : (deltaTick) ->				
		dirty = false		

		#if @is_flying() 
		@vel = @vel.mad deltaTick, gravity
		@vel.y = Math.min(@vel.y,TERMINAL_VELOCITY)		

		is_solid = (p) => @map.get_block_type(p.x,p.y) != 0
		
		delta = @vel.mul deltaTick		
		
		while delta.size()
			[new_pos,new_delta] = physics.walk @pos, delta, is_solid
			
			moved = not new_pos.equals @pos
			@pos = new_pos
			
			if new_delta.size()
				dirty = true 		if moved
				@vel.x = 0 			if new_delta.x

				if new_delta.y
					@flying = false	if @vel.y > 0
					@vel.y = 0

			break					if delta.equals new_delta
			delta = new_delta		

		unstable = dirty or @flying or @vel.size()

		unstable

	jump : (power) ->		
		if not @is_flying() and @is_on_solid()
			@flying = true
			@vel.y = -power


module.exports.Entity = Entity
