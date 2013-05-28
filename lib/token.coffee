redis = require 'redis'
_ = require 'underscore'

module.exports = (server) ->
	server.use 'deps'

	client = redis.createClient()
	sub = redis.createClient()

	sub.subscribe 'token:migrate'
	sub.subscribe 'token:migrated'

	fns = {}

	add_fn = (token,who,fn) ->
		k = [token,who].join()
		fns[k] = fn		

	drop_fn = (token,who) ->
		k = [token,who].join()
		g = fns[k]		
		delete fns[k]		
		g

	migration_waiting = {}
	migration_waiting.next = 0

	sub.on 'message', (channel,message) ->		
		if channel == 'token:migrate'
			#console.log channel,message
			[token, from, to, id] = JSON.parse message		
			
			drop_fn(token,from)? to, ->			
				client.publish 'token:migrated', id

		else if channel == 'token:migrated'
			#console.log 'token:migrated',message
			id = message
			o = migration_waiting[id]
			if o?
				o?()
				delete migration_waiting[id]
		
	migrate = (k,result,who,cb) ->		
		result = null if result == "null"
		if result and result != who
			#console.log 'long migratation',k,result,who
			id = [server.id,migration_waiting.next++].join(':')
			migration_waiting[id] = ->				
				cb()
			client.publish 'token:migrate', JSON.stringify [k, result, who, id]
		else
			cb()

	server.acquireToken = (who,k,fn,cb) ->		
		#console.log 'acquire', k, who
		fn ?= (taker,cb) -> cb()
		cb ?= ->
		client.getset k, who, (err,result) ->
			return cb(err) if err
			add_fn k, who, fn			
			migrate k,result,who,cb			

	server.destroyToken = (k,cb) ->
		return cb() unless k

		cb ?= ->
		client.getset k, null, (err,result) ->
			return cb(err) if err
			migrate k,result,null,cb

	server.releaseToken = (who,k,cb) ->
		cb ?= ->
		drop_fn k,who
		client.del k, cb

	server.on 'client:join', (client) ->
		client.on 'close', ->
			client.acquiredTokens?.map (token) => 
				server.destroyToken(token)

	Client = server.ClientClass

	Client::acquireToken = (k,fn,cb) ->				
		cb ?= ->
		fn ?= (taker,cb) -> cb()
		@acquiredTokens ?= []		
		if @acquiredTokens.indexOf(k) < 0
			myfn = (taker,cb) =>								
				i = @acquiredTokens.indexOf k				
				@acquiredTokens.splice(i,1) unless i<0				
				server.deps.write @

				@emit 'lost-token', k, taker		
				
				@destroyDependentTokens(k)
				@removeTokenFromDeps(k)
				@removeAliasedToken(k)

				fn taker, cb
			server.acquireToken String(@), k, myfn, (err,result) =>				
				return cb(err) if err
				@acquiredTokens.push k				
				server.deps.write @				
				cb()

	Client::destroyDependentTokens = (k) ->
		l = @token_deps?[k]				
		if l?					
			server.destroyToken(v) for v in l

	Client::removeTokenFromDeps = (k) ->
		if @token_deps
			for kk,v of @token_deps
				i = v.indexOf(k)					
				v.splice(i,1) unless i<0
				if v.length == 0
					delete @token_deps[kk]

	Client::removeAliasedToken = (k) ->
		if @token_aliases
			for k,v of @token_aliases
				if v == k
					delete @token_aliases[k]
					return

	Client::tokenAlias = (alias,k) ->
		if k?
			@token_aliases ?= {} 
			@token_aliases[alias] = k
		else
			@token_aliases?[alias]

	Client::releaseToken = (k,cb) ->
		if k instanceof RegExp
			for t in @acquiredTokens
				if k.test(t)
					@releaseToken(t)
		else
			i = @acquiredTokens?.indexOf k
			if i >= 0
				@acquiredTokens.splice(i,1)
				server.releaseToken String(@), k,cb

	Client::destroyToken = (k,cb) ->
		if k instanceof RegExp
			for t in @acquiredTokens
				if k.test(t)
					server.destroyToken(t)
		else
			server.destroyToken(t)

	Client::hasToken = (pat) ->		
		_.any @acquiredTokens, (x) -> pat.test(x)

	Client::token = (pat) ->
		if @acquiredTokens?
			for t in @acquiredTokens
				r = pat.exec(t)
				return r if r

	Client::tokenDeps = (which,other,cb) ->
		@token_deps ?= {}
		@token_deps[other] ?= []
		@token_deps[other].push(which)
		
		cb()


					
