ether = require './ether'
_ = require 'underscore'
async = require 'async'

plugins = 'express cluster mongodb rpc stats accounts'.split(' ')	
opts = 
	express : 
		port : 3338
	cluster : false
	mongodb: ['ether',[]]

server = ether(plugins,opts)

article_test = (col,root) ->
	server.publishDocs 'test', (client,cb) -> col.find({}).limit(10).sort when:-1,cb
	root.addItem = (client,msg,cb) -> col.save {author:client.tag(),msg:msg,when:Date.now()}, cb
	root.deleteItem = (client,id,cb) -> col.remove {_id:db.ObjectId(id),author:client.tag()},cb
	root.likeItem = (client,id,cb) -> 
		q = 
			_id:db.ObjectId(id)			
			liked:$not:$elemMatch:client.tag()
		u = 
			$push:liked:client.tag()
			$inc:like:1

		col.update q, u, db.expect('failed',cb,1)

server?.use 'room'
server?.use 'friends'
server?.use 'matchmaking'
server?.use 'shop'
server?.use 'world'

if server
	{db,rpc,deps} = server
	
	article_test (db.collection 'mycollection'), rpc.auth

	server.initialize (err) ->
		if err
			process.exit 'error'
		else
			console.log 'we are all online'.bold

	