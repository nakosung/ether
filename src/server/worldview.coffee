_ = require 'underscore'

# 'world' is evaluated when 'important' chunks are noisy
# if there are no events, publish function isn't evaluated at all! (performance-wise)
module.exports = (server) ->
	{deps} = server

	grab_for_client = (client) ->
		bag = {}

		from_chunk_view = (chunk_view) ->
			# for each all subscribed chunks
			for k,s of chunk_view.chunks
				if s?
					deps.read s.chunk

					# for each entities in the chunk
					for k,v of s.chunk.entities
						bag[k] = v

		# should include myself
		bag[client.avatar.id] = client.avatar

		if client.chunk_view
			from_chunk_view client.chunk_view, bag

		bag

	server.publish 'world', (client,old) ->		
		# relys on client state
		deps.read client

		world = client.avatar?.world
		return {} unless world

		avatars = {}

		visible_avatars = grab_for_client(client)
		
		# all visible avatars
		for id,a of visible_avatars
			o = old?.avatars?[id]

			# result
			r = null

			# if is updated or newly shown?
			if not o? or o.age != a.age 
				r = a.snapshot(client)
			# if is upto-date
			else 
				r = age:a.age
	
			# save off
			avatars[id] = r

		# this is the final payload
		payload = age:world.age, avatars:avatars

		# save 'sneaky' context with '$'
		$ = old?.$
		unless $?
			$ = context : {}				

		payload.$ = $		
		payload