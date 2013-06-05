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

		context = old?.$?.context or {}

		avatars = {}

		visible_avatars = {}
		visible_avatars[client.avatar.id] = client.avatar

		for k,s of chunk_view.chunks						
			for k,v of s?.chunk.entities
				visible_avatars[k] = v
		
		for id,a of visible_avatars
			o = old?.avatars?[id]
			r = null
			if o?.age != a.age or not o?
				r = a.snapshot(client)
			else if o?.age == a.age
				r = age:a.age
			else
				return	
			r.owned = true if (client.avatar == a)
			avatars[id] = r

		payload = age:world.age, avatars:avatars

		$ = payload.$ = context : context

		$.diff = (old,curr,diff_fn) ->
			diff_fn old, curr

		payload