_ = require 'underscore'

module.exports = (server) ->
	{deps} = server

	server.publish 'world', (client,old) ->
		# relys on client state
		deps.read client

		world = client.avatar?.world
		chunk_view = client.chunk_view
		return {} unless world and chunk_view?

		# relys on world
		deps.read world				

		avatars = {}

		visible_avatars = {}

		# should include myself
		visible_avatars[client.avatar.id] = client.avatar

		# for each all subscribed chunks
		for k,s of chunk_view.chunks
			# for each entities in the chunk
			for k,v of s?.chunk.entities
				visible_avatars[k] = v
		
		# all visible avatars
		for id,a of visible_avatars
			o = old?.avatars?[id]

			# result
			r = null

			# if is updated or newly shown?
			if o?.age != a.age or not o?
				r = a.snapshot(client)
			# if is upto-date
			else if o?.age == a.age
				r = age:a.age
			# otherwise, skip it
			else
				return	

			# if we are owning it, mark it!
			r.owned = true if (client.avatar == a)

			# save off
			avatars[id] = r

		# this is the final payload
		payload = age:world.age, avatars:avatars

		# save 'sneaky' context with '$'
		$ = old?.$
		unless $?
			$ = 
				context : {}
				diff : (old,curr,diff_fn) -> diff_fn old, curr

		payload.$ = $		
		payload