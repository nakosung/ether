publish = require './publish'
cluster = require 'cluster'

# cluster support
module.exports = (server) ->
	unless cluster.worker?
		console.warn 'cluster: not inited, no clusters'.red
		return

	server.use 'redis'

	redis_sub.subscribe 'bridge'			
	server.redis.sub.on 'message', (channel,message) ->
		if channel == "bridge"
			[from,msg,args] = JSON.parse message
			unless from == server.id
				server.emit msg, args...
		
	server.bridge = (msg) ->				
		server.on msg, (args...) ->
			server.redis.pub.publish channel, JSON.stringify [server.id,msg,args]
		
	