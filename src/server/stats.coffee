module.exports = (server) ->
	server.use 'publish'

	server.publish 'stats', (client) -> 
		server.deps.read 'stats'
		numClients:server.clients.length

	server.on 'client:join', -> server.deps.write 'stats'
	server.on 'client:leave', -> server.deps.write 'stats'