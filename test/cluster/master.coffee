cluster = require 'cluster'
cluster.setupMaster 
	exec : __dirname + '/slave.js'
	args : []
	silent : false

module.exports = (command...,cb) ->
	worker = cluster.fork()
	worker.send JSON.stringify(command)
	tr = {}
	trid = 0
	worker.on 'message', (msg) ->											
		if msg.result		
			(msg.result[0]?).should.be.false
			cb()		
		if msg.rpcback			
			tr[msg.rpcback.id](msg.rpcback.args...)
			delete tr[msg.rpcback.id]
	worker.terminate = (cb) ->
		worker.send 'force kill'
		worker.once 'disconnect', cb

	worker.rpc = (args...,cb) ->
		id = trid++
		tr[id] = cb		
		worker.send JSON.stringify(rpc:[id,args])
	worker