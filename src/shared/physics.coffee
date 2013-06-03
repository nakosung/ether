{Vector} = require './vector'

# sweeping 1x1 from curPos to newPos ..
one = new Vector(1)
col = one
col_eps = col.sub new Vector(0.00001)

dim_range = [0..(Vector.dim-1)]

sweep = (p1,p2,is_solid) =>
	d = p2.sub(p1).size()
	if d > 1
		m = p1.add(p2).mul(0.5)
		#console.log p1, m, p2
		return sweep(p1,m,is_solid) or sweep(m,p2,is_solid)

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

	# if p1.x != p2.x
	# 	console.log 'should solve it'
	# 	console.log p1,p2,a0,a1,b0,b1,is_solid(b0),is_solid(b1)

	V = new Vector p2
	# a1-a0 = [0,col]
	# b1-b0 = [0,col]
	if a0.x != b0.x
		V.x = a0.x
	if a0.y != b0.y
		V.y = a0.y	
	unless is_solid(b0)
		if is_solid(b1) 
			if a0.equals b0			
				if a1.x != b1.x
					V.x = a0.x
				if a1.y != b1.y
					V.y = a0.y
			else
				V = new Vector a0
		else			
			if a0.x != b0.x
				if p1.x < p2.x
					V.x += 1
				else if p1.x > p2.x
					V.x -= 1
			if a0.y != b0.y
				if p1.y < p2.y
					V.y += 1
				else if p1.y > p2.y
					V.y -= 1

	#console.log V
	V

walk = (pos,delta,is_solid) ->
	s = delta.size()
	return [pos,delta] unless s

	sweep = (pos,delta,axis) ->		
		throw new Error('pos should be a vector') unless pos instanceof Vector
		throw new Error('delta should be a vector') unless delta instanceof Vector
		throw new Error('axis should be a vector') unless axis instanceof Vector
		a = axis.max_elem()
		dir = if delta.elem(a) > 0 then 1 else -1
		size = delta.size()
		n = delta.mul(1/size)

		# current position
		o = pos.elem(a) * dir

		# distance to go
		l = delta.elem(a) * dir

		# snap to grid
		# sweeping volume
		sv = [Math.floor(o)..Math.floor(o+l+1-0.0001)]

		col = new Vector(1 - 0.0001)
		col[a] = 0

		P = pos				

		for v in sv			
			k = v
			go = k - o
			p = pos.add(n.mul(go/Math.abs(n.elem(a))))
			#console.log p, n, go
			if is_solid(p.floor()) or is_solid(p.add(col).floor())				
				#console.log p.floor()
				newD = delta.sub(P.sub(pos))
				return [(go-1) * dir, [P, newD]]
			P = p			

		[size * dir,[pos.add(delta),new Vector()]]

	horz = null
	vert = null

	#console.log 'hello'

	if delta.x		
		horz = sweep(pos,delta,new Vector(1,0))		
	if delta.y
		vert = sweep(pos,delta,new Vector(0,1))

	#console.log "result", horz, vert

	if horz and vert
		if Math.abs(horz) < Math.abs(vert)
			D = new Vector(horz[1][1])
			saved = D.elem(0)
			D.elem(0,0)
			R = walk(horz[1][0],D,is_solid)
			R[1].elem(0,saved)
			return R
		else
			D = new Vector(vert[1][1])
			saved = D.elem(1)
			D.elem(1,0)
			R = walk(vert[1][0],D,is_solid)
			R[1].elem(1,saved)
			return R

	return horz[1] if horz
	return vert[1] if vert

	[pos.add(delta), new Vector()]	



module.exports.sweep = sweep
module.exports.walk = walk