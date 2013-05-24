redis = require 'redis'
publish = require './publish'
cluster = require 'cluster'

# cluster support
module.exports = (server) ->
	unless cluster.worker?
		console.warn 'cluster: not inited, no clusters'.red
		return
	
	redis_pub = redis.createClient()
	redis_sub = redis.createClient()
	
	redis_sub.on 'message', (channel,message) ->
		[from,args] = JSON.parse message
		unless from == server.id
			server.emit channel, args...
		
	server.bridge = (channel) ->
		redis_sub.subscribe channel
		server.on msg, (args...) ->
			redis_pub.publish channel, JSON.stringify [server.id,args]
		
	