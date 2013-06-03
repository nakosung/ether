class Vector
	constructor : (args...) ->
		@set args...

	toString : ->
		String([@x,@y])

	set : (args...) ->
		if args.length
			[a,b] = args
			if a == undefined
				@x = @y = 0
			else if a instanceof Object
				@x = a.x
				@y = a.y
			else 
				@x = a
				@y = b
				@y ?= a
		else
			@zero()

	add : (v) ->
		new Vector @x + v.x, @y + v.y

	sub : (v) ->
		new Vector @x - v.x, @y - v.y

	mul : (k) ->
		new Vector @x * k, @y * k

	mad : (k,v) ->
		new Vector v.x * k + @x, v.y * k + @y

	floor : () ->
		new Vector Math.floor(@x), Math.floor(@y)

	abs : () ->
		new Vector Math.abs(@x), Math.floor(@y)

	max_elem : ->
		if @x > @y 
			0
		else 
			1
	min_elem : ->
		if @x < @y
			0
		else
			1

	equals : (v) ->
		@x == v.x and @y == v.y

	square : ->			
		@x * @x + @y * @y

	elem : (i,val) ->
		if val == undefined
			switch i
				when 0 then @x
				when 1 then @y
		else
			switch i
				when 0 then @x = val
				when 1 then @y = val
			@

	size : ->
		Math.sqrt @square()

	zero : ->
		@x = @y = 0

	dot : (v) ->
		v.x * @x + v.y * @y


Vector.dim = 2

module.exports.Vector = Vector
