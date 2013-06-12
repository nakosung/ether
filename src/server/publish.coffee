events = require 'events'
jsondiffpatch = require 'jsondiffpatch'
_ = require 'underscore'
assert = require 'assert'

module.exports = (server) ->
	pubs = {}

	server.use? 'deps'	

	deps = server.deps

	assert(deps)
	
	class Source extends events.EventEmitter
		constructor : (@fn) ->

	class Collection
		constructor:(@client,@name) ->
			@watch = server.deps.watch => @sync()

			@source = pubs[@name]			
			if @source
				@source.on 'update', => @sync()
			@snapshot = {}
			@sync()			

		destroy : ->
			@watch.destroy()			

		grab : (cb) ->
			internal = (p,cb) =>						
				unless p?				
					return cb(null,[{channel:@name,unknown:true}])				
				else if _.isFunction p
					fin = (err,result) ->
						return cb(err) if err
						internal result, cb
					
					r = null

					@watch.begin()

					arity = p.length
					async = (arity == 3)
					if async
						p.call null,@client,@snapshot,fin
					else
						r = p.call null,@client,@snapshot

					@watch.end()					

					fin(null,r) unless async
				else if _.isObject p				
					cb(null,p)
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
						$ = curr.$
						delete curr['$']

						old = @snapshot
						diff_fn = jsondiffpatch.diff

						if $?.diff?
							diff = $.diff old, curr, diff_fn
						else
							diff = diff_fn old, curr

						if diff
							#console.log "diffing", @name, "D".green.bold, curr, old, diff
							#diff = curr
							@snapshot = JSON.parse JSON.stringify curr							
							@client.send channel:@name, diff:diff
							@snapshot.$ = $ if $
						
					if @queued
						@queued = false
						@sync()

	update = @update = (pub) -> pubs[pub].emit 'update'

	server.publish = @publish = (pub,fn) ->	
		s = new Source(fn)
		s.update = -> update pub
		pubs[pub] = s
		s.update

	server.unpublish = @unpublish = (pub) ->
		delete pubs[pub]

	class Client
		constructor : (@client) ->
			@reqs = {}

			@client.on 'close', (client) =>				
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

	server.subscribe = (channel,client) ->
		client.subs = new Client(client) unless client.subs?
		client.subs.subscribe channel

	server.unsubscribe = (channel,client) ->
		client.subs.unsubscribe channel
	
	server.on 'client:data', (client,json) ->
		if json.req
			server.subscribe json.req, client

		if json.unreq and client.subs			
			server.unsubscribe json.req, client

	server.on 'publish:update', (pub) ->
		pubs[pub]?.emit 'update'

