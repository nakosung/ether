# Deps manages data dependency, it mimics Meteor's reactiveness.
# Data scope is defined by tuple; [DATASET,KEY], KEY can be omitted or be set as '*' to match everything.

# If cluster module is introduced, Deps automatically utilizes distributed power of redis.

_ = require 'underscore'
module.exports = (server) ->
	# shared private function for read/write
	write = (target,dep,extra) ->
		if extra == '*'
			target[dep] = '*'
		else if target[dep] != '*'
			target[dep] ?= []
			target[dep].push extra if target[dep].indexOf(extra) < 0

	class Watcher
		constructor : (@deps,fn,watching) ->
			if watching?
				if _.isArray(watching)
					@watching = {}
					watching.forEach (x) => @watching[x] = '*'
				else 
					@watching = watching
			else
				@watching = {}

			watchFn = (written) =>
				# for all of dirties
				for k, v of written
					w = @watching[k]
					if w? 
						# all is dirty, listens to everything or we have exact matches.
						if w == '*' or v == '*' or _.intersection(w,v).length
							# call user defined function immediately without callback
							fn()
							# no needs to evaluate loop
							break

			# we are listening
			server.on 'dep:update', watchFn

			# for graceful exit
			@release = =>
				server.removeListener 'dep:update', watchFn

		# destroy doesn't destroy anything but unsubscribe event
		destroy : ->
			@release()

		# user module can call begin/end pair.
		begin : ->
			@deps.watching = true
			@deps.deps = {}						
		
		end : ->					
			@watching = @deps.deps
			@deps.watching = false
			@deps.deps = null

	class Deps
		constructor : ->					
	
		# instantiate a watch
		watch : (fn,watching) -> new Watcher(@,fn,watching)

		# needs something?
		read : (dep,extra) =>			
			write @deps, String(dep), String(extra or '*') if @deps				

		write : (dep,extra) ->						
			unless @written?
				@written = {}

				# In order to implement minimal buffer, 'actual call' is deferred to next tick instead of calling immediately.
				process.nextTick =>
					server.emit 'dep:update', @written
					@written = undefined

			write @written, String(dep), String(extra or '*')

	server.deps = new Deps()
	server.bridge? 'dep:update'