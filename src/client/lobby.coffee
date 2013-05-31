require './ether'

app = angular.module('lobby',['ui','ui.bootstrap','ether','ui.directives'])

	# $scope.$watch ->		
	# 	if not $scope.me? and $location.path() != '/'
	# 		$location.path '/'

app.controller 'RoomCtrl', ($scope,collection,rpc,autologin,autocol,subscribe) ->	
	autocol $scope, 'myroom me'	

	$scope.rpc = rpc		
	setInterval (->	rpc.room?.in?.claimOwner() unless collection.all.myroom?.owner?), 1000

	$scope.chat = []

	sub = subscribe /^room:/, (channel,message) ->
		$scope.chat.push "#{message.joined} has joined" if message.joined?
		$scope.chat.push "#{message.left} has left" if message.left?
		$scope.chat.push [message.sender, message.chat].join(':') if message.chat?
		$scope.chat = _.last($scope.chat,5)

	$scope.$on '$destroy', ->
		sub()

app.controller 'FriendsCtrl', ($scope,autocol,rpc) ->	
	autocol $scope, 'me'	
	$scope.rpc = rpc		

	$scope.autocompleteSuggesions = (req,res) ->		
		rpc.auth.list.users req.term, (err,result) ->			
			unless err
				res(result) 
			else
				res([])

app.controller 'HomeCtrl', ($scope,autocol,rpc) ->
	$scope.rpc = rpc

app.controller 'ShopCtrl', ($scope,autocol,rpc) ->
	autocol $scope, 'sku'
	$scope.rpc = rpc
	$scope.edit = (sku) ->
		console.log 'editing', sku
		$scope.editing = 
			target:sku
			actions : 
				Modify : -> 
					doc = 
						_id : sku._id
						name : sku.name
						price : sku.price
					rpc.shop.keeper.update sku._id, doc, (err) ->
						unless err
							$scope.editing = undefined
						
				Cancel : -> $scope.editing = undefined			
			

app.controller 'ShopKeeperCtrl', ($scope,rpc) ->
	$scope.sku = {}
	$scope.rpc = rpc
	context = {}
	$scope.editing = 
		target : context
		actions :
			Create : ->
				console.log context
				rpc.shop.keeper.add context, (err) ->					
					unless err
						delete context[k] for k,v of context

app.controller 'SKUEditorCtrl', ($scope,rpc) ->	
	$scope.$watch 'editing', ->
		$scope.target = $scope.editing?.target

