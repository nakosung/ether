require './ether'
{Vector} = require '../shared/vector'
_ = require 'underscore'
logic = require './logic'

app = angular.module('world',['ui','ui.bootstrap','ether','ui.directives'])

app.directive 'playground', ->
	restrict : 'E'
	transclude : true
	link : (scope,element,attrs) ->		
		width = parseInt(attrs.width) or 600
		height = parseInt(attrs.height) or 600		
		refreshRate = parseInt(attrs.framerate) or 30

		$(element).width(width).height(height)		
		$(element).playground {height: height, width: width, refreshRate: 1000/refreshRate, keyTracker: true}

		instance = null

		console.log 'playground created'

		init = ->
			return if instance
			instance = new scope[attrs.runner] scope, $.playground(), width:width,height:height,refreshRate:refreshRate		

		uninit = ->
			return unless instance
			$.playground().pauseGame()
			$.playground().clearAll(true)
			instance.destroy()
			instance = null

		init()

		A = scope.$on 'sockjs.offline', ->
			uninit()

		B = scope.$on 'sockjs.online', ->
			init()
		
		scope.$on '$destroy', ->
			A()
			B()
			uninit()

app.factory 'world', (rpc,autocol,$rootScope) ->	
	


	class World
		constructor : (@scope, @pg,@opts) ->
			@entities = {}			

			console.log 'creating a world'

			@map = new logic.ClientMap(@pg,width:@opts.width,height:@opts.height)

			enter = =>
				console.log 'trying to enter'
				if rpc.world?.enter?
					@handler?()
					@handler = null

					rpc.world.enter (err,server_settings) =>
						@server_settings = server_settings
						console.log 'enter returned', err, server_settings
						if err
							console.error(err)
						else
							@init()
				else
					console.error 'no rpc for now'

			@handler = $rootScope.$on 'rpc:update', (x) => enter()

			enter()

			@sprite_id = 0

		createEntity : (opt) ->
			#console.log 'createEntity', opt
			{id,pos,vel,age} = opt
			@entities[opt.id] = e = new logic.ClientEntity(@map,id,pos,vel,age)
			sprite_id = "sprite#{@sprite_id++}"
			@pg.addSprite sprite_id, posx:e.pos.x,posy:e.pos.y,animation:@block,geometry:$.gQ.GEOMETRY_RECTANGLE
			e.sprite = $("#"+sprite_id)		

			@updateEntity opt

		updateEntity : (opt) ->			
			#console.log 'updateEntity', opt
			e = @entities[opt.id]						
			e.age = opt.age
			e.localAge = 0
			e.pos.set opt.pos			
			e

		deleteEntity : (opt) ->
			#console.log 'deleteEntity', opt

			e = @entities[opt.id]
			e?.sprite?.remove()
			@avatar = undefined if e == @avatar
			delete @entities[opt.id]

		init : ->			
			@initialized = true
			@block = new $.gQ.Animation imageURL:'img/24x24.gif'		
			
			@pg.startGame()

			deltaTick = @server_settings.framerate/@opts.refreshRate			
			@pg.registerCallback (=>@tick(deltaTick)), 1000/@opts.refreshRate

			@avatar = null
			@angular_spin = 0			

			@keymap =
				left:65
				right:68
				up:87
				down:83
				space:32

			@packet_handler = $rootScope.$on 'sockjs.json', (e,json) =>	
				return unless json.world?

				@handlePacket json.world			

			@measureTimeDiffAndRoundtrip (err) =>
				unless err
					rpc.world.hello (err) =>
						unless err
							@map.set_pos 0,0			
						else
							console.error('INIT FAILED')
				else
					console.error 'error!'

		measureTimeDiffAndRoundtrip : (cb) ->
			clientTime = Date.now()
			rpc.world.time Date.now(), (err,time) =>
				now = Date.now()
				if err
					cb(err)
				else
					@time = diff:time-clientTime,rtt:now-clientTime
					cb()

		keypressed : (key) ->
			$.gQ.keyTracker[@keymap[key] or key.charCodeAt(0)]		

		handlePacket : (json) ->
			#console.log json
			
			@avatar = @createEntity(json.spawn) if json.spawn?
			@createEntity(json.add) if json.add?
			@updateEntity(json.update) if json.update?
			@deleteEntity(json.remove) if json.remove?
			if json.chunk?
				@map.give_chunk json.chunk.key, json.chunk.buf
			if json.chunk_changed?
				data = json.chunk_changed
				chunk = @map.chunks[data.key]
				chunk?.emit 'remotely_changed', data.args...

		tick : (deltaTick) ->			
			get_dir = =>
				dir = new Vector 0,1
				if @keypressed 'left'
					dir = new Vector -1, 0
				else if @keypressed 'right'
					dir = new Vector 1, 0
				else if @keypressed 'up'
					dir = new Vector 0, -1
				dir
			if @avatar?
				@map.fit @avatar.pos

				VELOCITY = 0.3

				actions = []

				if @keypressed 'left'
					@avatar.vel.x = -VELOCITY
				else if @keypressed 'right'
					@avatar.vel.x = +VELOCITY
				else
					@avatar.vel.x = 0

				if @keypressed 'space'
					@avatar.jump 1

				if @keypressed 'J'	
					rpc.world.actions.dig get_dir()

				if @keypressed 'K'
					rpc.world.actions.put get_dir(), 2

			@currentTick ?= 0
			@currentTick += deltaTick
			intTick = Math.floor @currentTick
									
			for k,e of @entities
				if e == @avatar and @lastTick != intTick
					@lastTick = intTick				
					if e.tick 1						
						rpc.world.update.unreliable pos:e.pos, vel:e.vel				
				else
					e.simulate e.localAge
			
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
	document.oncontextmenu = -> false
	$(document).mousedown (e) ->
		if e.button == 2
			false
		true
	$scope.runner = world