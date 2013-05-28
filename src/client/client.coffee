app = angular.module('client',['ui','ui.bootstrap','ether','ui.directives'])

app.controller 'MainCtrl', ($scope,collection,rpc,autologin,autocol) ->	
	autocol $scope, 'myroom test me sync:stat users_online stats mm rooms'	
	$scope.rpc = rpc	
	setInterval (->	rpc.room?.in?.claimOwner() unless collection.all.myroom?.owner?), 1000

	$scope.autocompleteSuggesions = (req,res) ->		
		rpc.auth.list.users $scope.targetUser, (err,result) ->
			res(result) unless err

	window.rpc = rpc
	window.col = collection.all
		