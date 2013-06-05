module.exports = (server) ->
	sockjs = require 'sockjs'
	@sockjs = sockjs.createServer log:-> # silent sock.js!
	@sockjs.on 'connection', (conn) => 
		client = new @ClientClass("#{@id}:#{@nextClientId++}",conn)			

		client.on 'raw', (raw) => @emit 'client:raw', client, raw
		client.on 'data', (data) => @emit 'client:data', client, data
		conn.once 'close', => 
			client.destroy()
			i = @clients.indexOf client
			@clients.splice i,1
			@emit 'client:leave', client

		@on 'client-src:changed', => client.sendraw 'client-src:changed'

		@clients.push client			
		@emit 'client:join', client	


