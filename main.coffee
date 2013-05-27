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

server?.use 'room'

if server
	{db,rpc,deps} = server
	
	article_test (db.collection 'mycollection'), rpc.auth

	server.listen()

	