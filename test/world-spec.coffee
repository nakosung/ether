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

	describe 'hit wall', ->
		map = "first line
		oooooooooo
		o........o
		o......o.o
		o....ooooo
		o........o
		o........o
		oooooooooo".split('\t\t').splice(1)

		sizex = map[0].length
		sizey = map.length

		is_solid = (pos) ->
			{x,y} = pos
			x < 0 or y < 0 or x >= sizex or y >= sizey or map[y][x] == 'o'
		
		test_walk = (s,e) ->
			physics.walk s, e, is_solid
		
		it 'should walk right', ->			
			(test_walk new Vector(2,5), new Vector(8,0))[0].should.eql new Vector(8,5)
			(test_walk new Vector(2,5), new Vector(8,0))[1].should.eql new Vector(2,0)

		it 'should walk left', ->			
			(test_walk new Vector(2,5), new Vector(-4,0))[0].should.eql new Vector(1,5)
			(test_walk new Vector(2,5), new Vector(-4,0))[1].should.eql new Vector(-3,0)

		it 'should walk right w/gravity', ->			
			(test_walk new Vector(2,5), new Vector(8,3))[0].should.eql new Vector(8,5)
			(test_walk new Vector(2,5), new Vector(8,3))[1].should.eql new Vector(2,3)

		it 'should not fall thru', ->			
			(test_walk new Vector(2,5), new Vector(0,3))[0].should.eql new Vector(2,5)
			(test_walk new Vector(2,5), new Vector(0,3))[1].should.eql new Vector(0,3)

		it 'should walk left', ->			
			(test_walk new Vector(5,2), new Vector(4,6))[0].should.eql new Vector(6,2)
			(test_walk new Vector(5,2), new Vector(4,6))[1].should.eql new Vector(3,6)





