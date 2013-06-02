{Vector} = require './vector'
{Map,CHUNK_SIZE_MASK} = require './map'

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
			console.log deltaTick, @vel, @vel.mad deltaTick, gravity
			@vel = @vel.mad deltaTick, gravity

		newPos = @pos.mad deltaTick, @vel

		# curPos can occupy several blocks max upto 2^dim
		# newPos also occupied upto 2^dim

		c = (x,y) => @map.get_block_type(x,y) != 0

		is_solid = (p) => @map.get_block_type(p.x,p.y) != 0

		# sweeping 1x1 from curPos to newPos ..
		col = new Vector(1)
		col_eps = col.sub new Vector(0.00001)
		walk= (p1,p2) =>
			diff = p2.sub(p1)
			V = new Vector p2

			start = p1.floor() + new Vector(-1)
			end = p2.add(col_eps).floor() + new Vector(1)

			walls = [1..Vector.dim].map -> []	
			shouldCheckCorners = true

			for dim in [1..Vector.dim]
				v = diff.elem(dim)
				s = start.elem(dim)
				e = end.elem(dim)
				if v 
					p = if v > 0 then e else s
					for y in [(s + 1)..(e - 1)]
						x = (new Vector p).elem(dim,y)
						if is_solid(x)
							walls[dim].push x
							shouldCheckCorners = false
			
			end_col = p2.add col
			for dim in [1..Vector.dim]
				v = diff.elem(dim)
				for wall in walls[dim]
					collided = true
					for dim2 in [1..Vector.dim]
						if dim2 != dim
							ec = end_col.elem(dim2)
							w = wall.elem(dim2)
							unless ec > w and e < w + 1
								collided = false
					if collided
						if v > 0 
							V.elem dim, wall.elem(dim) - col.elem(dim)
						else if v < 0
							V.elem dim, wall.elem(dim) + 1

			if shouldCheckCorners
				console.log "TODO"

			V







		walk @pos, newPos

		nx = Math.floor(@pos.x)
		ny = Math.floor(@pos.y)
		mx = Math.floor(newPos.x)
		my = Math.floor(newPos.y)
		fx = nx != @pos.x
		fy = ny != @pos.y
		gx = mx != newPos.x
		gy = my != newPos.y

		
		@pos = newPos
		if @vel.x
			if @vel.x > 0
				if c(nx + 1, ny) or fy and c(nx + 1, ny + 1)
					#console.log 'hit right', nx, mx
					@pos.x = nx
					@vel.x = 0
					dirty = true
			else 
				nx += 1 if fx 
				if c(nx - 1, ny) or fy and c(nx - 1, ny + 1)
					#console.log 'hit left', nx, mx
					@pos.x = nx
					@vel.x = 0
					dirty = true
				nx -= 1 if fx
			unless fy or c(nx, ny + 1) or fx and c(nx+1, ny+1)
				@flying = true
				dirty = true
		if @vel.y 
			if @vel.y > 0
				if c(nx, ny + 1) or fx and c(nx + 1, ny + 1)
					@pos.y = ny
					@vel.y = 0
					@flying = false
					dirty = true
			else 
				ny += 1 if fy
				if c(nx, ny - 1) or fx and c(nx + 1, ny - 1)
					@pos.y = ny
					@vel.y = 0
					dirty = true
					@flying = true
				ny -= 1 if fy

		#console.log fx,fy,nx,ny,mx,my,@pos,dirty,@vel

		# counter = 0
		# if Math.floor(@pos.y) == @pos.y 
		# 	if @map.is_empty(down)
		# 		@flying = true
		# 	else
		# 		@flying = false
		# 		if @vel.y > 0 
		# 			@vel.y = 0
		# else
		# 	while not @map.is_empty(@pos) and counter < 10
		# 		counter += 1
		# 		intY = Math.floor(@pos.y)
		# 		fracY = @pos.y - intY
		# 		@pos.y = intY - 1			
		# 		@flying = false
		# 		dirty = true
		# 		@vel.y = 0

		# 	if @vel.y 
		# 		@flying = true

		#console.log @pos, @vel, @flying
		
		dirty or @flying or @vel.size()

	jump : (power) ->		
		unless @is_flying()			
			@flying = true
			@vel.y = -power


module.exports.Entity = Entity
