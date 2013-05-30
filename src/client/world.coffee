app = angular.module('world',['ui','ui.bootstrap','ether','ui.directives'])

app.directive 'playground', ->
	restrict : 'E'
	transclude : true
	link : (scope,element,attrs) ->		
		width = parseInt(attrs.width) or 600
		height = parseInt(attrs.height) or 600		
		refreshRate = attrs.refreshRate or 30

		$(element).width(width).height(height)		
		$(element).playground {height: height, width: width, refreshRate: refreshRate, keyTracker: true}

		instance = new scope[attrs.runner] scope, $.playground(), width:width,height:height,refreshRate:refreshRate		
		
		scope.$on '$destroy', ->
			$.playground().pauseGame()
			$.playground().clearAll(true)
			instance.destroy()

app.factory 'world', (rpc,autocol,$rootScope) ->	
	class World
		constructor : (@scope, @pg,@opts) ->
			@entities = {}

			@handler = $rootScope.$on 'rpc:update', => enter()			

			enter = =>
				console.log 'trying to enter'
				if rpc.world?.enter?
					rpc.world.enter (err) =>
						console.log 'enter returned', err
						if err
							console.error(err)
						else
							@handler?()
							@handler = null
							@init()
				else
					console.log 'no rpc for now'

			enter()

			@sprite_id = 0

		createEntity : (opt) ->
			#console.log 'createEntity', opt
			@entities[opt.id] = e = opt
			sprite_id = "sprite#{@sprite_id++}"
			@pg.addSprite sprite_id, posx:@posx,posy:@posy,animation:@block,geometry:$.gQ.GEOMETRY_RECTANGLE
			e.sprite = $("#"+sprite_id)

			console.log @entities

			@updateEntity opt

		updateEntity : (opt) ->			
			#console.log 'updateEntity', opt

			e = _.extend @entities[opt.id], opt			
			e.sprite.xy(opt.x,opt.y) if opt.x? and opt.y?
			e

		deleteEntity : (opt) ->
			#console.log 'deleteEntity', opt

			e = @entities[opt.id]
			e?.sprite?.remove()
			@avatar = undefined if e == @avatar
			delete @entities[opt.id]

		init : ->
			console.log 'World::INIT'
			@initialized = true
			@block = new $.gQ.Animation imageURL:'img/24x24.gif'		
			
			@pg.startGame()

			@pg.registerCallback (=>@tick()), @opts.refreshRate

			@avatar = null
			@angular_spin = 0

			@speed = 3

			@keymap =
				65:'left'
				68:'right'
				87:'up'
				83:'down'

			@key_handlers =
				left: => @avatar.x -= @speed					
				right: => @avatar.x += @speed					
				up: => @avatar.y -= @speed					
				down: => @avatar.y += @speed

			inv_map = {}
			for k,v of @keymap
				inv_map[v] = k

			@key_processors = []

			for k,v of @key_handlers
				do (k,v) =>
					key_code = inv_map[k]
					fn = v

					@key_processors.push ->						
						if $.gQ.keyTracker[key_code]							
							fn()		
							false					
						else
							true

			@packet_handler = $rootScope.$on 'sockjs.json', (e,json) =>	
				return unless json.world?

				@handlePacket json.world

			rpc.world.hello()

		handlePacket : (json) ->
			#console.log json
			
			@avatar = @createEntity(json.spawn) if json.spawn?
			@createEntity(json.add) if json.add?
			@updateEntity(json.update) if json.update?
			@deleteEntity(json.remove) if json.remove?

		tick : ->					
			if @avatar?
				moved = not _.every @key_processors.map (x) -> x()							
				rpc.world.update.unreliable @avatar.x,@avatar.y if moved
				@avatar.sprite.xy(@avatar.x,@avatar.y)
			
			if @angular_spin-- < 0
				@angular_spin = @opts.refreshRate / 4							
				@scope.stats = 
					x : @avatar?.x
					y : @avatar?.y
				@scope.$apply()

			false

		destroy : ->
			if @initialized				
				@packet_handler()
				@packet_handler = null
				@initialized = false
				rpc.world.leave()

			@handler?()
			@handler = null

			console.log 'destroyed', @
	World

app.controller 'WorldCtrl', ($scope,rpc,world) ->	
	$scope.runner = world