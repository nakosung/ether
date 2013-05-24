_ = require 'underscore'

module.exports = (server) ->
	server.use 'publish'
	server.use 'deps'

	rpc = module.exports	
	server.rpc = rpc	

	rpc.assert_fn = (fn) ->
		throw new Error('function required') unless _.isFunction(fn)

	rpc.assert_fn.__check__ = false

	is_permitted = (client,fn) ->
		c = fn.__check__
		unless c? 
			true
		else unless _.isFunction(c)
			true
		else
			c(client)

	server.publish 'rpc', (client,cb) ->
		server.deps.read client

		client.rpc = {}

		walk = (rpc,parent=[]) ->
			for k,v of rpc
				if is_permitted(client,v)
					if _.isFunction(v)
						client.rpc[k] = fn:v,v:[parent...,v]
					else if _.isObject(v)
						walk(v,[parent...,v])

		walk(rpc)

		cb null, _.keys client.rpc

	server.on 'client:data', (client,data) ->
		return unless data.rpc?
		for k,v of data.rpc
			do (k,v) ->
				[trid,args...] = v

				cb = (r...) -> 
					unless trid == null
						client.send rpc:[trid,r...] 
					else 
						if r.length and r[0]
							client.send error:String(r[0])
						else
							client.send log:"OK"
				
				rr = client.rpc?[k]

				if rr?
					flags = rr.v.map (fn) -> is_permitted client, fn
					if _.all flags					
						try
							rr.fn.call rpc, client,args...,cb				
						catch e
							if e instanceof ReferenceError
								throw e
							else
								console.error e.error
								cb(e.error)						
					else
						console.log 'no permission', client.id, k
						cb('no permission')
				else
					cb('invalid')					
					

