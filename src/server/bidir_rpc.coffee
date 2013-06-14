# This module provides bidirectional RPC on tcp-socket.
# TODO: support arbtrary stream and furthermore dgrams!!!

events = require 'events'
carrier = require 'carrier'

module.exports = (c) ->
	trs = {}
	trid = 0

	class Holder extends events.EventEmitter
		invoke : (args...,cb) ->
		#	console.log 'invoke',args
			id = trid++
			trs[id] = cb
			c.write ">"
			c.write JSON.stringify [id,args...]
			c.write '\r\n'

	holder = new Holder()

	my_carrier = carrier.carry(c)
	my_carrier.on 'line', (data) =>		
		if data[0] == '<'
			#console.log '<<<<'.bold, data
			[trid,result...] = JSON.parse(data.substr(1))
			fn = trs[trid]
			delete trs[trid]
			fn?.apply null,result
		else if data[0] == '>'
			#console.log '>>>>'.bold, data
			[trid,args...] = JSON.parse(data.substr(1))
			cb = (r...) ->
				c.write "<"
				c.write JSON.stringify [trid,r...]
				c.write "\r\n"
			holder.emit 'invoke', args..., cb
		else
			#console.log '--l-'.bold, data
			holder.emit 'line', data

	c.on 'close', ->
		for k,v of trs 
			v('disconnected')
		trs = {}
		holder.removeAllListeners()

	holder