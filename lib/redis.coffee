# for sharing redis connection :)

redis = require 'redis'

module.exports = (server) ->
	pub = redis.createClient()
	sub = redis.createClient()
	
	server.redis = 
		pub : pub
		sub : sub

	subs = {}

	sub.on 'message', (channel,message) ->
		for s in subs[channel] or []
			s channel, JSON.parse(message)

	server.pub = (channel,message) ->
		@redis.pub.publish channel, JSON.stringify(message)

	server.sub = (channel,fn) ->
		unless subs[channel]?
			subs[channel] = [fn]
			@redis.sub.subscribe channel
		else
			subs[channel].push(fn)

	server.unsub = (channel,fn) ->
		i = subs[channel].indexOf fn
		subs[channel].splice(i)

