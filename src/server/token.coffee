_ = require 'underscore'
async = require 'async'

module.exports = (server) ->
	server.use 'deps'
	server.use 'redis'

	exclusive = (require './exclusive') {id:server.id,pub:server.redis.pub,sub:server.redis.sub}	

	server.acquireToken = (who,k,fn,cb) ->		
		fn2 = (taker...,cb) =>
			if who == taker[0]
				cb()
			else
				fn(taker[0],cb)
		exclusive.take k,fn2,who,cb

	server.readToken = (k,cb) ->
		exclusive.read k.cb

	server.destroyToken = (k,cb) ->
		return cb() unless k

		exclusive.destroy k,cb	

	server.releaseToken = (who,k,cb) ->
		exclusive.destroy k,cb

	server.on 'client:join', (client) ->
		client.on 'close', ->
			client.acquiredTokens?.map (token) => 
				server.destroyToken token, ->

	Client = server.ClientClass

	Client::acquireToken = (k,fn,cb) ->				
		throw new Error('invalid key') unless _.isString(k)
		throw new Error('invalid fn') unless _.isFunction(fn) or _.isUndefined(fn)
		throw new Error('invalid cb') unless _.isFunction(cb)
		cb ?= ->
		fn ?= (taker,cb) -> cb()
		@acquiredTokens ?= []		
		if @acquiredTokens.indexOf(k) < 0
			myfn = (taker,cb) =>			
				i = @acquiredTokens.indexOf k				
				@acquiredTokens.splice(i,1) unless i<0				
				server.deps.write @

				console.log "LOST_TOKEN", k

				@emit 'lost-token', k, taker		
				
				@removeTokenFromDeps(k)
				@removeAliasedToken(k)

				async.series [
					(cb) => @destroyDependentTokens k, cb
					(cb) => fn taker, cb				
				], cb
			server.acquireToken String(@), k, myfn, (err,result) =>				
				return cb(err) if err
				@acquiredTokens.push k				
				server.deps.write @				
				cb()
		else
			cb('already acquired')

	Client::destroyDependentTokens = (k,cb) ->
		jobs = []
		l = @token_deps?[k]				
		if l?					
			for v in l
				jobs.push (cb) -> server.destroyToken v,cb
		async.parallel jobs, cb

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
			jobs = []
			for t in @acquiredTokens
				if k.test(t)
					jobs.push (cb) -> server.destroyToken t, cb
			async.parallel jobs, cb
		else
			server.destroyToken k, cb

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


					
