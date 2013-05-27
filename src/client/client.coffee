app = angular.module('client',['ui','ui.bootstrap','ether'])

app.controller 'MainCtrl', ($scope,collection,rpc) ->
	$scope.collection = collection
	$scope.data = collection('test').data
	$scope.stats = collection('stats').data	
	$scope.clients = collection('clients').data	
	$scope.myself = -> collection('users:self').data
	$scope.myroom = -> collection('myroom').data
	window.rpc = rpc
	$scope.rpc = rpc	
	setInterval (->	rpc.room?.in?.claimOwner() unless $scope.myroom()?.owner?), 1000