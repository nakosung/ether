app = angular.module('client',['ui','ui.bootstrap','ether','ui.directives'])

app.controller 'MainCtrl', ($scope,collection,rpc,autologin,autocol,subscribe) ->	
	autocol $scope, 'myroom test me sync:stat users_online stats mm rooms mm:stats sku'	
	$scope.rpc = rpc	

	window.rpc = rpc
	window.col = collection.all	

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

	