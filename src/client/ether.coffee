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

	class Collection 
		constructor:(@name) ->
			@init() if sockjs.online 

			$rootScope.$on 'sockjs.online', => @init()
			$rootScope.$on 'sockjs.offline', => @uninit()			

			@data = undefined

			$rootScope.$on 'sockjs.json', (e,json) =>
				return unless json.channel == @name
				@data ?= {}
				jsondiffpatch.patch @data, json.diff				
				if _.keys(@data).length == 0
					@data = undefined								

				$rootScope.$broadcast "collection:update", @
		init : -> sockjs.send req:channel:@name
		uninit : -> @data = undefined

	(name) ->
		unless collections[name]
			collection = new Collection(name)
			collections[name] = collection
		collections[name]

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
						


	
	instance

