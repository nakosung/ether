events = require 'events'
async = require 'async'
session = require '../cell/session'
assert = require 'assert'
jsondiffpatch = require 'jsondiffpatch'

module.exports = (server) ->
	server.use 'deps'
	server.use 'cell'
	server.use 'rpc'
	server.use 'publish'

	{cell,deps,rpc} = server

	logic =
		server : (tissueServer) ->
			assert tissueServer
			session.server tissueServer

			tissueServer.on 'cell', (cell) ->
				class Publisher
					constructor : ->
						@deps = deps
						(require '../publish') @

				pub = new Publisher()

				# internal private state				
				text = []
				pub.publish 'chat', (sink,old) =>
					deps.read cell
					text:text

				cell.once 'close', ->
					console.log 'chat room closed'
					pub.unpublish 'chat'

				cell.on 'node', (node) ->
					class Sink extends events.EventEmitter 
						# pushed from publisher
						send : (json) ->
							node.invoke_remote 'sync', json, ->

					sink = new Sink
					pub.subscribe sink, 'chat'

					node.on 'close', ->
						sink.emit 'close'

					node.on 'session', (session) ->
						say = (what,cb) -> 
							text.push [session.id,what]
#							console.log 'saying', [session.id,what]
							deps.write cell
							cb?()					
						
						session.methods['say'] = say						

						session.once 'close', =>							
							say 'left'

						say 'joined'				

		client : (tissueClient) ->
			assert tissueClient
			session.client tissueClient

			server.publish 'chat', (client) ->				
				deps.read client
				deps.read client.chat_context.name if client.chat_context?
				client.chat_context?.data or {}				

			rpc.chat = 
				open : (client,cell,cb) ->			
					tissueClient.cell(cell).join(client,cb)
				__expand__ : (client) ->
					client.chats

			tissueClient.on 'cell', (cell) ->
				chat_context = {name:cell.cell,data:{}}
				cell.methods['sync'] = (json,cb) ->
					jsondiffpatch.patch chat_context.data, json.diff
					deps.write chat_context.name
					cb()

				cell.on 'session', (session) ->
					client = session.session					
					session.on 'online', ->
						client.chat_context = chat_context
						client.chats ?= {}
						client.chats[cell.cell] =
							close : (client,cb) -> session.leave cb
							say : (client,what,cb) -> session.invoke_remote 'say', what, cb
						deps.write client
					session.on 'offline', ->
						delete client.chat_context
						client.chats[cell.cell] = {}
						deps.write client						
	
	cell.server {name:'chat'}, (tissueServer) ->
		logic.server tissueServer
		console.log 'simple-chat server'.bold

	cell.client {name:'chat'}, (tissueClient) ->
		logic.client tissueClient
		console.log 'simple-chat client'.bold
