_ = require 'underscore'

module.exports = (server) ->
	db = server.db

	server.use 'publish'

	auto = (fn) ->		
		old_col = []		
		
		(args...,cb) ->					
			self = @

			update = (new_col) ->
				if new_col.length != old_col.length or (_.without new_col, old_col...).length					
					col.removeListener self for col in old_col				
					old_col = new_col
					col.on 'update', self for col in new_col
						
			fin = (err,result) ->					
				cb(err,result)

			fn.__begin = ->
				fn.result = []
				server.emit 'db:watch', fn.result

			fn.__end = ->
				update(fn.result)
				fn.result = undefined
				server.emit 'db:watch'

			fn.__begin()
			r = fn.call null,args...,fin
			fn.__end()			
			
			fin(null,r) if _.isObject(r)

	server.autopublish = (name,fn) ->
		server.publish name, auto fn
