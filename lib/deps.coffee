_ = require 'underscore'

module.exports = (server) ->
	class Deps
		constructor : ->		
	
		watch : (fn,watching) ->			
			deps = @

			class Watcher
				constructor : (fn,@watching = []) ->								
					watchFn = (array) =>						
						if _.intersection(@watching,array).length
							process.nextTick =>								
								fn()

					server.on 'dep:update', watchFn

					@release = =>
						server.removeListener 'dep:update', watchFn

				destroy : ->
					@release()

				begin : ->
					deps.watching = true
					deps.deps = {}						
				
				end : ->					
					keys = _.keys deps.deps
					deps.watching = false
					deps.deps = null

					@watching = keys

			new Watcher(fn,watching)

		read : (dep) => 			
			dep = String(dep)
			@deps[dep] = true if @deps

		write : (dep) ->
			dep = String(dep)
			unless @written?
				@written = []
				process.nextTick =>
					server.emit 'dep:update', @written
					@written = undefined

			@written.push dep if @written.indexOf(dep) < 0

	server.deps = new Deps()
	server.bridge? 'dep:update'