_ = require 'underscore'

module.exports = (server) ->
	server.use 'publish'
	server.use 'deps'

	rpc = module.exports	
	server.rpc = rpc	

	rpc.assert_fn = (fn) ->
		throw new Error('function required') unless _.isFunction(fn)

	rpc.assert_fn.__check__ = false

	rpc.wrap = (check,fn) ->
		fn.__check__ = check
		fn
	rpc.wrap.__check__ = false

	is_permitted = (client,fn) ->
		c = fn.__check__
		unless c? 
			true
		else unless _.isFunction(c)
			true
		else
			c(client)

	server.publish 'rpc', (client,old,cb) ->
		server.deps.read client

		client.rpc = {}

		walk = (rpc,prefix='',parent=[],context=null) ->
			for k,v of rpc
				if is_permitted(client,v)
					if _.isFunction(v) 
						if k == '__expand__'
							result = v.call(rpc,client)
							walk result, prefix, parent, context
						else if k != '__check__' 
							client.rpc[prefix+k] = fn:v,v:[parent...,v],context:context
					else if _.isObject(v)
						unless v.constructor == Object
							context = v
						walk(v,prefix+k+":",[parent...,v],context)

		walk(rpc)

		o = {}
		for k,v of client.rpc
			o[k] = true

		cb null, o

	server.on 'client:data', (client,data) ->
		return unless data.rpc?
		for k,v of data.rpc
			do (k,v) ->
				[trid,args...] = v

				cb = (r...) -> 
					unless trid == null
						client.send rpc:[trid,r...] 
					else if trid != -1						
						if r.length and r[0]
							client.send error:String(r[0])
						else
							r = r.splice(1)
							if r.length == 0 
								r = "OK"
							client.send log: r
				
				rr = client.rpc?[k]

				if rr?
					flags = rr.v.map (fn) -> is_permitted client, fn
					if _.all flags					
						try
							rr.fn.call rr.context or rpc, client,args...,cb				
						catch e
							if e instanceof ReferenceError or e instanceof TypeError
								throw e
							else
								console.error e
								cb(e.error)						
					else
						console.log 'no permission', client.id, k
						cb('no permission')
				else
					cb('no such rpc:'+k)					
					

