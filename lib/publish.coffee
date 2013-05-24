events = require 'events'
jsondiffpatch = require 'jsondiffpatch'
_ = require 'underscore'

module.exports = (server) ->
	pubs = {}

	server.use 'deps'	

	class Source extends events.EventEmitter
		constructor : (@fn) ->

	class Collection
		constructor:(@client,@name) ->
			@watch = server.deps.watch => @sync()

			@source = pubs[@name]			
			if @source
				@source.on 'update', => @sync()
			@snapshot = []
			@sync()			

		destroy : ->
			@watch.destroy()
			@watch = undefined

		grab : (cb) ->
			internal = (p,cb) =>						
				unless p?				
					return cb(null,[{channel:@name,unknown:true}])
				else if _.isArray p				
					cb(null,p)
				else if _.isFunction p
					fin = (err,result) ->
						return cb(err) if err
						internal result, cb
					
					r = null

					@watch.begin()
					r = p.call null,@client,fin
					@watch.end()					

					fin(null,r) if _.isObject(r)
				else				
					cb(null,[{channel:@name,unsupported:true}])

			if @source
				internal @source.fn,cb
			else
				cb('fail')

		sync : ->				
			if @syncing
				@queued = true
			else
				@syncing = true
				@grab (err,curr) =>					
					@syncing = false
					
					unless err
						old = @snapshot
						diff = jsondiffpatch.diff old, curr		
						@snapshot = curr
						@client.send channel:@name, diff:diff
						
					if @queued
						@queued = false
						@sync()

	update = @update = (pub) -> pubs[pub].emit 'update'

	server.publish = @publish = (pub,fn) ->	
		s = new Source(fn)
		s.update = -> update pub
		pubs[pub] = s
		s.update

	class Client
		constructor : (@client) ->			
			@reqs = {}

			server.on 'client:leave', (client) =>
				if client == @client
					@destroy()

		destroy : ->
			v.destroy() for k,v of @reqs				

			@reqs = undefined
			@client.subs = undefined

		subscribe : (req) ->						
			name = req.channel
			unless @reqs[name]
				@reqs[name] = new Collection(@client,name)

		unsubscribe : (req) ->
			name = req.channel
			@reqs[name]?.destroy()
			delete @reqs[name]
	
	server.on 'client:data', (client,json) ->	
		if json.req
			client.subs = new Client(client) unless client.subs?		
			client.subs.subscribe json.req

		if json.unreq and client.subs			
			client.subs.unsubscribe json.unreq

	server.on 'publish:update', (pub) ->
		pubs[pub]?.emit 'update'


