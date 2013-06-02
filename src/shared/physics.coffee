{Vector} = require './vector'

# sweeping 1x1 from curPos to newPos ..
one = new Vector(1)
col = one
col_eps = col.sub new Vector(0.00001)

dim_range = [0..(Vector.dim-1)]

walk = (p1,p2,is_solid) =>
	d = p2.sub(p1).size()
	if d > 1
		m = p1.add(p2).mul(0.5)
		return walk(p1,m,is_solid) or walk(m,p2,is_solid)

	a0 = p1.floor()
	a1 = p1.add(col_eps).floor()

	b0 = p2.floor()
	b1 = p2.add(col_eps).floor()

	# start invalid
	if is_solid(a0) or is_solid(a1)
		return p1

	# safe end
	unless is_solid(b0) or is_solid(b1)
		return undefined

	console.log 'should solve it'
	console.log a0,a1,b0,b1,p1,p2
	
	V = new Vector p2
	if p1.x != p2.x
		V.x = a0.x
	if p1.y != p2.y
		V.y = a0.y

	console.log V
	V

module.exports.sweep = walk