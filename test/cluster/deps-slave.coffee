async = require 'async'
{EventEmitter} = require 'events'
ether = require '../../src/server/ether'

module.exports = () ->		
	server = ether ['cluster','deps'], id:'mocha-slave'
	
	async.series [
		(cb) -> server.initialize(cb)
		(cb) ->			
			process.on 'message', (msg) ->
				try					
					msg = JSON.parse(msg)				
					if msg.rpc											
						[id,args] = msg.rpc
						[command,args...] = args						
						cb = (args...) -> process.send rpcback:{id:id,args:args}
						switch command
							when 'write' 
								server.deps.write args...
								cb()
							else
								cb('invalid command')		
				catch e
			process.send result:[]
			cb()
		(cb) -> server.exit(cb)
	], ->	

	