require './lobby'
require './world'

app = angular.module('client',['lobby','world'])

app.config [
	'$routeProvider', ($routeProvider) ->
		$routeProvider.
			when('/', templateUrl:'template/home.html', controller:'HomeCtrl').
			when('/shop', templateUrl:'template/shop.html', controller:'ShopCtrl').
			when('/world', templateUrl:'template/world.html', controller:'WorldCtrl').
			otherwise redirectTo:'/'
]

app.controller 'NavCtrl', ($scope,$location,rpc) ->
	class NavMenu
		constructor : (@name,@path,@checker) ->
		is_active : -> $location.path() == @path

	menu = [
		new NavMenu 'Home', '/', -> true
		new NavMenu 'Shop', '/shop', -> rpc.shop?
		new NavMenu 'World', '/world', -> rpc.world?
	]

	$scope.$on 'rpc:update', ->		
		$scope.navbar = _.filter menu, (m) -> m.checker()
	
app.controller 'MainCtrl', ($scope,collection,rpc,autologin,autocol,subscribe,$location) ->	
	autocol $scope, 'myroom test me sync:stat users_online stats mm rooms mm:stats'	
	$scope.rpc = rpc	

	window.rpc = rpc
	window.col = collection.all		