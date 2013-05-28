ether = angular.module('ether',[])
# main proxy
ether.factory 'sockjs', ($rootScope) ->		
	class Server
		constructor : ->						
			@handleConnectionLost()

			$rootScope.$on 'sockjs.json', (e,json) =>				
				console.error json.error if json.error?
				console.log json.log if json.log?

		updateAngularJs : ->			
			!$rootScope.$$phase && $rootScope.$apply()

		handleConnectionLost : ->
			if @heartbeat?
				clearTimeout(@heartbeat) 
				@heartbeat = undefined

			@online = false
			$rootScope.$broadcast 'sockjs.offline', @			
			@updateAngularJs()				

			@sock = new SockJS('/sockjs')
			@sock.onopen = => @initSock()
			@sock.onclose = => setTimeout (=> @handleConnectionLost()), 250				

		initSock : () ->							
			@online = true					

			# message handler
			@sock.onmessage = (e) =>
				window.location.reload() if e.data == 'client-src:changed'
				$rootScope.$broadcast "sockjs.raw", e
				try
					data = JSON.parse(e.data)
					$rootScope.$broadcast "sockjs.json", data					
				catch exception
					# silently failed

				@updateAngularJs()				

			$rootScope.$broadcast 'sockjs.online', @
			@updateAngularJs()

			@heartbeat = setInterval (=>
				@send heartbeat:true
				), 10000

		send : (json) -> @sock.send JSON.stringify(json)		
	
	new Server()

ether.factory 'collection', (sockjs,$rootScope) ->
	collections = {}
	all = {}

	class Data
		array : ->
			_.values(@)

	class Collection 
		constructor:(@name) ->
			@init() if sockjs.online 
			@safe_name = @name.replace(':','_')

			$rootScope.$on 'sockjs.online', => @init()
			$rootScope.$on 'sockjs.offline', => @uninit()			

			@data = undefined

			$rootScope.$on 'sockjs.json', (e,json) =>
				return unless json.channel == @name
				@data ?= new Data
				jsondiffpatch.patch @data, json.diff				
				if _.keys(@data).length == 0
					@data = undefined

				@sync()
				$rootScope.$broadcast "collection:update", @
		init : -> sockjs.send req:channel:@name
		uninit : -> 
			@data = undefined
			@sync()
		sync : ->
			return if all[@safe_name] == @data

			all[@safe_name] = @data
			$rootScope.$broadcast "collection:sync", @

	ret = (name) ->
		if name?
			unless collections[name]
				collection = new Collection(name)
				collections[name] = collection
			collections[name]
	ret.all = all
	ret

ether.factory 'autocol', (collection,$rootScope) ->
	(container,cols) ->		
		cols = cols.split(' ') unless _.isArray(cols)
		update = ->			
			for c in cols
				col = collection(c)
				container[col.safe_name] = col.data
		$rootScope.$on 'collection:sync', update
		update()

ether.factory 'rpc', (sockjs,$rootScope,collection) ->
	rpc_dir = collection('rpc')

	instance = {}

	next_trid = 0
	trs = {}

	$rootScope.$on 'sockjs.json', (e,json) =>		
		return unless json.rpc? 

		[trid,args...] = json.rpc
		trs[trid]?(args...)
		delete trs[trid]
	
	$rootScope.$on 'collection:update', (e,collection) ->
		if collection == rpc_dir
			delete instance[k] for k of instance
			for method,v of collection.data
				do (method) ->					
					fn = instance[method] = (args...,cb) ->
						trid = null
						if cb?
							if _.isFunction(cb)
								trid = next_trid++
								trs[trid] = cb
							else
								args.push cb 

						t = rpc:{}						
						t.rpc[method] = [trid,args...]
						console.log t.rpc
						sockjs.send t
					o = method.split(':')
					if o.length > 1
						i = instance
						while o.length > 1
							oo = o.shift()
							i[oo] ?= {}
							i = i[oo]
						i[o.shift()] = fn
			$rootScope.$broadcast 'rpc:update'					
	instance

ether.factory 'autologin', ($rootScope,rpc) ->
	class AutoLogin
		constructor : ->
			@cred = null		
			@install()

			# there can be two clients racing against one account :)
			# only the last valid client can re-connect
			$rootScope.$on 'rpc:update', =>
				@install()
				if @cred and rpc.noauth? and @mayTry
					@mayTry = false
					rpc.noauth.login(@cred.name,@cred.pwd)					
			
			$rootScope.$on 'sockjs.offline', =>
				@mayTry = rpc.auth?				

		install : ->
			if rpc.noauth?.login? and not rpc.noauth.login.__installed
				org = rpc.noauth.login
				rpc.noauth.login.__installed = true
				rpc.noauth.login = (name,pwd,args...) =>
					@store(name,pwd)
					org(name,pwd,args...)

			if rpc.auth?.logout? and not rpc.auth.logout.__installed
				org = rpc.auth.logout
				rpc.auth.logout.__installed = true
				rpc.auth.logout = (args...) =>
					@clear()
					org(args...)

		store : (name,pwd) ->
			@cred = name:name,pwd:pwd
			true
		clear : ->
			@cred = null
			true

	new AutoLogin()
