require './ether'
{Vector} = require '../shared/vector'
_ = require 'underscore'
logic = require './logic'

TILE_SIZE = 24

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

app.factory 'world', (rpc,autocol,$rootScope,$location) ->	
	class World
		constructor : (@scope, @pg,@opts) ->
			@entities = {}			

			console.log 'creating a world'

			@map = new logic.ClientMap(@pg,width:@opts.width,height:@opts.height)

			@players = @pg.addGroup "players", width:@pg.width(), height:@pg.height()

			enter = =>
				console.log 'trying to enter'
				if rpc.world?.enter?
					@handler?()
					@handler = null

					rpc.world.enter (err,server_settings) =>
						@server_settings = server_settings
						console.log 'enter returned', err, server_settings

						# error occurred, we cannot enter into the world! *SAD*
						if err
							# route to 'root'
							$location.path '/'
						else
							@init()
				else
					console.error 'no rpc for now'

			@handler = $rootScope.$on 'rpc:update', (x) => enter()
			@view = {}

			enter()

			@sprite_id = 0

		createEntity : (id,opt) ->
			#console.log 'createEntity', id, JSON.stringify(opt)
			{pos,vel,age} = opt
			@entities[opt.id] = e = new logic.ClientEntity(@map,id,pos,vel,age)
			sprite_id = "sprite#{@sprite_id++}"
			GROUP_WIDTH = 200
			GROUP_HEIGHT = 100
			e.group = @players.addGroup sprite_id, width:GROUP_WIDTH, height:GROUP_WIDTH
			e.group.addSprite "real"+sprite_id, width:TILE_SIZE,height:TILE_SIZE,animation:@block,geometry:$.gQ.GEOMETRY_RECTANGLE
			e.group.xy e.pos.x,posy:e.pos.y
			e.sprite = $("#"+sprite_id)	
			e.tag = $("<div/>")
			e.tag.text id
			e.tag.css
				color:'yellow'
				position:'relative'
				top:'-20px'
				'text-align':'center'
				'font-size':'9px'
				left:-Math.floor(100 - TILE_SIZE/2) + 'px'
				width:GROUP_WIDTH + 'px'
			e.tag.appendTo(e.sprite)

			@updateEntity id,opt

		updateEntity : (id,opt) ->			
			#console.log 'updateEntity', id, JSON.stringify(opt)
			e = @entities[id]
			if e
				e.age = opt.age
				e.localAge = 0

				if opt.pos? and opt.vel?				
					e.pos.set opt.pos	
					e.vel.set opt.vel		
				e
			else
				console.log 'invalid'


		deleteEntity : (id) ->
			#console.log 'deleteEntity', opt

			e = @entities[id]
			e?.group?.remove()
			@avatar = undefined if e == @avatar
			delete @entities[id]

		init : ->			
			@initialized = true
			@block = new $.gQ.Animation imageURL:'img/tiles24x24.png', offsetx:24*0, offsety:24*9
			
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

			@view_handler = $rootScope.$on "collection:update", (e,collection) =>
				@handleView collection.data if collection.name == "world"

			@packet_handler = $rootScope.$on 'sockjs.json', (e,json) =>	
				return unless json.world?

				@handlePacket json.world

			@measureTimeDiffAndRoundtrip (err) =>
				unless err
					rpc.world.hello (err) =>
						if err
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

		handleView : (data) ->
			newView = {}

			for k,v of data.avatars				
				unless @view[k]?
					e = @createEntity(k,v)
					@avatar = e if v.owned
				else
					if @view[k] < v.age
						@updateEntity(k,v)

					delete @view?[k]

				newView[k] = v.age
			
			for k,v of @view
				@deleteEntity(k)

			@view = newView

		handlePacket : (json) ->
			#console.log json			
			
			if json.chunk_changed?
				data = json.chunk_changed
				chunk = @map.chunks[data.key]
				chunk?.emit 'remotely_changed', data.args...

		processInput : ->
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

				VELOCITY = 0.25

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

		tickEntities : (deltaTick)->
			@currentTick ?= 0
			@currentTick += deltaTick
			intTick = Math.floor @currentTick
									
			for k,e of @entities
				e.localAge += deltaTick
				if e == @avatar and @lastTick != intTick
					e.localAge = 0
					@lastTick = intTick				
					if e.tick 1						
						rpc.world.update.unreliable pos:e.pos, vel:e.vel				
				else					
					e.simulate e.localAge		

		tickStats : ->			
			if @angular_spin-- < 0
				@angular_spin = @opts.refreshRate / 4							
				@scope.stats = 
					x : @avatar?.pos.x
					y : @avatar?.pos.y
				@scope.$apply()

		tick : (deltaTick) ->			
			@processInput()
			@tickEntities(deltaTick)
			@tickStats()

			false

		destroy : ->
			if @initialized				
				@packet_handler()
				@view_handler()
				@packet_handler = @view_handler = null
				@initialized = false
				rpc.world.leave()

			@handler?()
			@handler = null

			console.log 'destroyed', @
	World

app.controller 'WorldCtrl', ($scope,rpc,world,autocol) ->	
	autocol $scope, 'world'	
	document.oncontextmenu = -> false
	$(document).mousedown (e) ->
		if e.button == 2
			false
		true
	$scope.runner = world