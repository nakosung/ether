async = require 'async'

module.exports = (server) ->
	server.use 'accounts'

	{rpc} = server

	players = []

	class Avatar
		constructor : (@client) ->
			@x = Math.floor Math.random() * 500
			@y = Math.floor Math.random() * 500

			@id = client.id						

			players.forEach (p) =>
				@send add: id:p.id, x:p.x, y:p.y				
				p.send add: id:@id, x:@x, y:@y		

			players.push(@)
			@send spawn:id:@id,x:@x,y:@y		
				

		send : (json) -> @client.send world:json

		update : (x,y,cb) ->			
			@x = x
			@y = y
			players.forEach (p) =>
				return if p == @

				p.send update:id:@id,x:@x,y:@y

			cb()

		destroy : ->
			players.forEach (p) =>
				return if p == @

				p.send remove:id:@id

			players.splice players.indexOf(@), 1

	rpc.world =
		__check__ : rpc.auth.__check__

		enter : (client,cb) ->
			@assert_fn cb			

			fn = (taker,cb) ->				
				client.avatar?.destroy()
				delete client.avatar
				cb()

			token = 'avatar:'+client.auth

			async.series [
				(cb) -> client.destroyToken token, cb
				(cb) -> client.acquireToken token, fn, cb
				(cb) -> client.tokenDeps token, (client.tokenAlias 'auth'), cb				
			], (err) ->				
				cb(err)			

		hello : (client,cb) ->			
			if client.avatar?
				cb('already helloed')
			else
				client.avatar = new Avatar(client)
				cb()

		update : (client,x,y,cb) ->
			return cb('invalid state') unless client.avatar?
			client.avatar.update(x,y,cb)

		leave : (client,cb) ->
			client.destroyToken 'avatar:'+client.auth, cb