module.exports = (server) ->	
	server.use 'cell'	

	{cell} = server

	cell.server {name:'simple'}, (tissueServer) ->		
		console.log 'simple-cell server'.bold

	cell.client {name:'simple'}, (tissueClient) ->		
		console.log 'simple-cell client'.bold
