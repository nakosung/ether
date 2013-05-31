{Vector} = require './vector'
{Map,CHUNK_SIZE_MASK} = require './map'

gravity = new Vector 0,0.2

class Entity
	constructor : (@map,@id,pos,vel) ->			
		@pos = new Vector pos
		@vel = new Vector vel

	is_flying : ->
		@flying

	tick : (deltaTick) ->				
		dirty = false		

		if @is_flying()
			@vel = @vel.mad deltaTick, gravity
		else
			if @vel.y > 0 
				@vel.y = 0

		counter = 0
		while not @map.is_empty @pos and counter < 10
			counter += 1
			intY = Math.floor(@pos.y)
			fracY = @pos.y - intY
			@pos.y = intY - 1			
			@flying = false
			dirty = true
			@vel.y = 0

		if @vel.y 
			@flying = true

		console.log @pos, @vel, @flying

		newPos = @pos.mad deltaTick, @vel
		if @map.is_empty(newPos)
			@pos = newPos
		else
			@vel.zero()
		if @vel.square() > 0
			dirty = true

		dirty

	jump : (power) ->		
		unless @is_flying()			
			@vel.y = -power


module.exports.Entity = Entity
