ether = require './lib/ether'
_ = require 'underscore'
async = require 'async'

plugins = 'coffee-script cluster mongodb rpc stats accounts'.split(' ')	
opts = 
	cluster : false
	mongodb: ['ether',[]]

server = ether(plugins,opts)

article_test = (col,root) ->
	server.publish 'test', (client,cb) -> col.findAll({},cb)	
	root.addItem = (client,cb) -> 
		col.save {hello:'world'}, cb
	root.deleteItem = (client,id,cb) -> 
		col.remove {_id:db.ObjectId(id)},cb
	root.likeItem = (client,id,cb) -> 
		col.update {_id:db.ObjectId(id)},$inc:like:1, cb

#server?.use 'room'

if server
	{db,rpc,deps} = server

	hooks = require 'hooks'
	class Entity 
		constructor : (@name,@col) ->
		create : (doc,cb) ->
			@col.save doc, cb
		pre : (e,fn) ->
			unless @[e].org?
				org = @[e]
				proxy = (args...) =>
					fn = =>
						org.call @, args...
					proxy.pre fn, args... 
				proxy.org = org
				proxy.pre = fn
				@[e] = proxy
				


	Room = new Entity 'room', db.collection('room')
	Room.pre 'create', (next,doc,cb) ->
		console.log 'create'
		next(doc,cb)

	member_of = (G) ->
		server.ClientClass::set_group = (g) ->
			@[group] = g
			deps.write @

		group = G.name
		col = G.col
		actions = 
			create : (opt,cb) ->
				doc = {}
				_.extend doc, opt
				doc.users = [@auth]
				async.waterfall [
					(cb) -> G.create doc, cb
					(doc,cb) => 
						@set_group doc._id
						cb()
				], cb
			leave : (cb) ->
				async.series [
					(cb) => col.update {_id:@[group]}, {$pull:users:@auth}, cb
					(cb) => col.remove {_id:@[group],users:[]}, cb
					(cb) =>
						@set_group undefined
						deps.write @
						cb()
				], cb
		server.on 'client:join', (client) ->
			client.on 'login', ->
				console.log client.auth

		bind = (fn) -> (client,args...) -> fn.call client, args...
		rpc.auth[group] = 
			in:
				__check__ : (client) -> client[group]?
				leave : bind actions.leave
			out:
				__check__ : (client) -> not client[group]?
				create : bind actions.create
					

	member_of Room
	
	article_test (db.collection 'mycollection'), rpc.auth

	server.listen()

	