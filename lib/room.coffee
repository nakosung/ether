_ = require 'underscore'
async = require 'async'

module.exports = (server) ->
	# only auth. users can access to rooms :)
	server.use 'accounts'

	{db,rpc,deps} = server		

	rooms = db.collection 'rooms'

	server.publish 'rooms', (client,cb) -> rooms.findAll({},cb)

	# cleanup
	rooms.remove {}
	#db.users.remove {}

	set = (group,col,root) ->
		group_owner = group + "_owner"

		class DbAccessor
			constructor : (member) ->
				@member = (x) ->
					r = {}
					r[member] = x
					r
				@id = (g,x) ->
					x ?= {}
					x._id = g
					x
			expect_one : (cb) ->
				(err,result) ->
					if result == 1
						cb()
					else
						cb(err or 'invalid:'+result)

		class Collection extends DbAccessor
			constructor : (@col,member) ->
				super member

			add : (g,m,cb) ->
				@col.update @id(g,@member($ne:m)), {$push:@member(m)}, @expect_one(cb)
			remove : (g,m,cb) ->
				@col.update @id(g,@member(m)), {$pull:@member(m)}, @expect_one(cb)

		class Single extends DbAccessor
			constructor : (@col,member) ->
				super member
			add : (g,m,cb) ->
				@col.update @id(g,@member(null)), {$set:@member(m)}, @expect_one(cb)
			remove : (g,m,cb) ->
				@col.update @id(g,@member(m)), {$unset:@member(1)}, @expect_one(cb)

		class ClientLocal
			constructor : (@member) ->
			add : (g,m,cb) ->
				return cb('invalid.client local'+g[@member]) if g[@member]

				g[@member] = m
				deps.write g
				cb()

			remove : (g,m,cb) ->
				return cb('invalid') unless g[@member]
				
				g[@member] = undefined
				deps.write g
				cb()

		class RelationshipMux
			constructor : ->
				@forwards = []
				@backwards = []

			forward : (R) ->
				@forwards.push R

			backward : (R) ->
				@backwards.push R

			add : (g,m,cb) ->
				async.parallel [
					(cb) => async.parallel (@forwards.map (x) -> (cb) -> x.add g,m,cb), cb
					(cb) => async.parallel (@backwards.map (x) -> (cb) -> x.add m,g,cb), cb
				], cb
			remove : (g,m,cb) ->
				async.parallel [
					(cb) => async.parallel (@forwards.map (x) -> (cb) -> x.remove g,m,cb), cb
					(cb) => async.parallel (@backwards.map (x) -> (cb) -> x.remove m,g,cb), cb
				], cb

		class Transform
			constructor : (@R,opts) ->
				@g = opts?.g or (x) -> x
				@m = opts?.m or (x) -> x

			add : (g,m,cb) ->
				@R.add @g(g), @m(m), cb
			remove : (g,m,cb) ->
				@R.remove @g(g), @m(m), cb

		G = new Collection rooms,'users' 
	#	M = new Single db.users,'room'
		C = new ClientLocal 'room_at'
		R = new RelationshipMux
		
		R.forward new Transform G, m:(x) -> x.auth
	#	R.backward new Transform M, g:(x) -> x.auth
		R.backward C

		OM = new Single rooms, 'owner'
		OC = new ClientLocal 'owns_room'
		OR = new RelationshipMux

		OR.forward new Transform OM, m:(x) -> x.auth
		OR.backward OC

		server.publish "my#{group}", (client,cb) ->
			deps.read client
			if client.room_at?
				G.col.findAll G.id(client.room_at,users:client.auth), (err,docs) ->
					cb(err,docs)
					unless docs.length
						R.remove client.room_at, client, -> 

			else
				cb(null,[])

		server.on 'client:join', (client) ->
			client.once 'logout', ->
				R.remove client.room_at, client, ->
			
		root.in = 
			__check__ : (client) -> client.room_at?
			# owner :
			# 	__check__ : (client) -> client.owns_room?
			# 	kick : (client,opp,cb) ->	
			# 		client[group].kick(opp,cb)
			leave : (client,cb) ->
				R.remove client.room_at, client, cb
		root.out = 
			__check__ : (client) -> not client.room_at?
			create : (client,opt,cb) ->		
				return cb('already in') if client.room_at? 

				doc = title:'unnamed'		
				_.extend doc, opt		
				# doc.owner = @auth
				col.save doc, (err,doc) =>			
					return cb(err) if err			
					@at = doc._id
					# @is_owner = true
					R.add doc._id, client, (err,result) =>
						console.log "********".bold
						console.log err,result
						console.log client.room_at
						cb(err,result)

			join : (client,g,cb) ->		
				R.add db.ObjectId(g),client, cb
				

	set('room',rooms,rpc.auth.room = {})