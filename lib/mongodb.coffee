mongojs = require 'mongojs'
events = require 'events'
_ = require 'underscore'

last_fn = (args) ->
	if _.isFunction _.last(args) then args.pop() else ->

module.exports = (server,opt) ->	
	server.use 'deps'

	server.publishDocs = (pub,fn) ->
		server.publish pub, (client,cb) ->
			fn client,(err,docs) ->
				return cb(err) if err

				o = {}
				for doc in docs
					o[doc._id] = doc
				cb(null,o)
	server.publishDoc = (pub,fn) ->
		server.publish pub, (client,cb) ->
			fn client,(err,doc) ->				
				return cb(err) if err

				cb(null,doc or {})

	class Instance
		constructor : ->
			server.db = @	

			[host,collections] = opt	

			db = null	
			
			readSources = []

			class Proxy extends events.EventEmitter
				constructor : (@org,@name) ->
					@dep_name = "mongodb:" + @name

				toString : ->
					@dep_name

				read : ->
					server.deps.read @dep_name

					if readSources
						readSources.push @ unless ~readSources.indexOf @

				find : (args...) ->
					@read()				

					@org.find(args...)

				findOne : (args...) ->
					@read()				

					@org.findOne(args...)


				# meteor like helper
				findAll : (args...) ->
					cb = last_fn(args)

					p = @find(args...)
					r = []
					p.forEach (err,doc) =>
						unless doc						
							cb(null,r)
						else
							r.push doc

				findAndModify : (args...) ->
					cb = last_fn(args)

					@read()

					@org.findAndModify args..., (r...) =>
						@invalidate()
						cb(r...)

				update : (args...) ->
					cb = last_fn(args)

					@org.update args..., (r...) =>
						@invalidate()
						cb(r...)		

				save : (args...) ->			
					cb = last_fn(args)

					@org.save args..., (r...) =>
						@invalidate()
						cb(r...)

				remove : (args...) ->			
					cb = last_fn(args)

					@org.remove args..., (r...) =>
						@invalidate()
						cb(r...)

				ensureIndex : (args...) -> @org.ensureIndex args...				

				invalidate : ->
					server.deps.write @
					@emit 'update'	

			server.on 'db:watch', (target) -> 		
				readSources = target	
					
			@ObjectId = mongojs.ObjectId		

			@collections = []

			add_collection = (name,org) =>
				@collections.push @[name] = new Proxy(org,name)		

			@collection = (name) =>
				add_collection name,db.collection(name) unless @[name]					
				@[name]

			db = mongojs host, collections
			for collection in collections
				org = db[collection]
				add_collection(collection,org)			

		# test returned result matches to given args.
		# test is limited to the length of args like a pattern matching.
		expect : (error,cb,args...) ->
			(err,result...) ->		
				#console.log 'expecting',args,'->',result
				if err
					cb(err)
				else 
					for v,i in args
						if v? and v != result[i]
							return cb(error)
					cb()

		expectNot : (error,cb,args...) ->
			(err,result...) ->		
				#console.log 'expecting',args,'->',result
				if err
					cb(err)
				else 
					for v,i in args
						if v? and v == result[i]
							return cb(error)
					cb()

	new Instance()
