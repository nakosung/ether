{Vector} = require './vector'

# sweeping 1x1 from curPos to newPos ..
one = new Vector(1)
col = one
col_eps = col.sub new Vector(0.00001)

dim_range = [0..(Vector.dim-1)]

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

	# console.log 'hello'

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

module.exports.walk = walk