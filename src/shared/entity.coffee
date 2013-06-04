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
		if @vel.y > TERMINAL_VELOCITY
			@vel.y = TERMINAL_VELOCITY

		c = (x,y) => @map.get_block_type(x,y) != 0

		is_solid = (p) => @map.get_block_type(p.x,p.y) != 0

		
		delta = @vel.mul deltaTick
		#console.log "tick", @id, @pos, @vel, @flying, delta
		
		while delta.size()			
			#console.log 'gogo'
			try
				[@pos,new_delta] = physics.walk @pos, delta, is_solid					
				#console.log [@pos,new_delta]
				if new_delta.size()				
					dirty = true
					if new_delta.x
						@vel.x = 0
					if new_delta.y
						if @vel.y > 0
							#console.log 'clear flying'
							@flying = false
						@vel.y = 0					
				if delta.equals new_delta
					break
				delta = new_delta
			catch e
				console.error e
			

		# unless dirty or @flying or @vel.size()
		# 	console.log 'freeze', @pos, @vel, delta, @flying
		
		dirty or @flying or @vel.size()

	jump : (power) ->		
		if not @is_flying() and @is_on_solid()
			@flying = true
			@vel.y = -power


module.exports.Entity = Entity
