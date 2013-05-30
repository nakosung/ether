app = angular.module('client',['lobby','world'])

app.config [
	'$routeProvider', ($routeProvider) ->
		$routeProvider.
			when('/', templateUrl:'template/home.html', controller:'HomeCtrl').
			when('/shop', templateUrl:'template/shop.html', controller:'ShopCtrl').
			when('/world', templateUrl:'template/world.html', controller:'WorldCtrl').
			otherwise redirectTo:'/'

]

app.controller 'NavCtrl', ($scope,$location) ->
	class NavMenu
		constructor : (@name,@path) ->
		is_active : -> $location.path() == @path

	$scope.navbar = [
		new NavMenu 'Home', '/'
		new NavMenu 'Shop', '/shop'
		new NavMenu 'World', '/world'
	]

app.controller 'MainCtrl', ($scope,collection,rpc,autologin,autocol,subscribe,$location) ->	
	autocol $scope, 'myroom test me sync:stat users_online stats mm rooms mm:stats'	
	$scope.rpc = rpc	

	window.rpc = rpc
	window.col = collection.all		