{Vector} = require '../src/shared/vector'

describe 'Vector', ->
	describe 'cons', ->
		it 'should create vector from undefined', ->
			(new Vector)
		it 'should construct from scalar', ->
			(new Vector(2)).equals new Vector([1..Vector.dim].map -> 2)
	describe 'elem', ->
		it 'should fetch elem with dim', ->
			(new Vector(1)).elem(1).should.equal(1)
		it 'should save elem', ->
			(new Vector(2)).elem(1,0).elem(1).should.equal 0
	describe 'arithmetics', ->
		it 'should not alter unnecessary dim', ->
			(new Vector(1)).sub(new Vector().elem(1,0)).elem(0).should.equal 1
			(new Vector(1)).sub(new Vector().elem(0,0)).elem(1).should.equal 1


physics = require '../src/shared/physics'

describe 'physics', ->
	describe 'basic', ->
		it 'should not crash', ->
			is_solid = -> false
			physics.sweep new Vector(1), new Vector(2), is_solid

	describe 'hit wall', ->
		map = "first line
		oooooooooo
		o........o
		o........o
		o........o
		o........o
		o........o
		oooooooooo".split('\t\t').splice(1)

		sizex = map[0].length
		sizey = map.length

		is_solid = (pos) ->
			{x,y} = pos
			x < 0 or y < 0 or x >= sizex or y >= sizey or map[y][x] == 'o'

		test = (s,e) ->
			physics.sweep s, e, is_solid

		# it 'should cut', ->
		# 	(test new Vector(1.5,2), new Vector(0,2)).x.should.equal 1

		# it 'should not alter unnecessary dim elem', ->
		# 	(test new Vector(2,2), new Vector(sizex+1,2)).y.should.equal 2

		it 'should collide right wall', ->
			(test new Vector(2,2), new Vector(sizex+1,2)).x.should.equal sizex-2





