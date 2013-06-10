module.exports = (server) ->
	server.use 'deps'
	server.use 'cell'
	server.use 'rpc'

	{cell,deps,rpc} = server

	class CellInstance 
		constructor : (@cell) ->	
			
		init : (cb) ->
			console.log 'example cell init', @cell
			cb()
		
		client : (client) ->
			client.id

		init_client : (client,cell,interfaces) ->
			client.cells ?= {}
			client.cells[cell] = interfaces
			deps.write client

		uninit_client : (client,cell) ->
			delete client.cells[cell]
			deps.write client

		destroy : (cb) ->
			console.log 'destroying this cell', @cell
			cb()

		hello : (client,msg,cb) ->			
			cb(null,"hello back #{client}. this is #{@cell}.")	
	
	config = 
		name : 'dumbcell'
		user_class : CellInstance

	cell.server config, ->
		console.log 'simple-cell'.bold

	cell_client = cell.client config
	
	rpc.cell =
		open : (client,cell,cb) ->			
			cell_client.cell(cell).join(client,cb)

		__expand__ : (client) ->
			client.cells
