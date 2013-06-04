publish = require './publish'
cluster = require 'cluster'
redis = require 'redis'

# cluster support
module.exports = (server,opt) ->
	pub = opt?.pub or redis.createClient()
	sub = opt?.sub or redis.createClient()

	# it prevents neverending ping-pong
	gate = false
	
	server.bridge = (msg) ->								
		server.on msg, (args...) ->	
			unless gate
				pub.publish "bridge", JSON.stringify [server.id,msg,args]	
	
	init : (done) ->						
		sub.on 'message', (channel,message) ->		
			if channel == "bridge"			
				[from,msg,args] = JSON.parse message
				unless from == server.id
					gate = true
					server.emit msg, args...
					gate = false

		sub.subscribe 'bridge'					
		
		sub.once 'subscribe', (channel,count) -> done()
		