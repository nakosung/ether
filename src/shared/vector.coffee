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

	equals : (v) ->
		@x == v.x and @y == v.y

	square : ->			
		@x * @x + @y * @y

	size : ->
		Math.sqrt @square()

	zero : ->
		@x = @y = 0

module.exports.Vector = Vector
