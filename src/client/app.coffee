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
	autocol $scope, 'chat:cluster chat myroom test me sync:stat users_online stats mm rooms mm:stats'	
	$scope.rpc = rpc	

	window.rpc = rpc
	window.col = collection.all		

app.controller 'ErrorDialogController', ($scope,dialog,args,result) ->
	$scope.close = -> dialog.close()	
	$scope.title = if result[0] then "Error" else "Success"
	$scope.args = args
	$scope.result = result


app.controller 'ModalCtrl', ($scope,$dialog) ->	
	last = null
	$scope.$on 'rpc:result', (e,json) ->		
		[args,result] = json		
		if last?.isOpen
			last.close()
		d = last = $dialog.dialog {
			backdrop:true
			keyboard:true
			backdropClick:true			
			resolve:
				result: -> angular.copy result
				args: -> angular.copy args
		}			
		d.open 'template/error.html', 'ErrorDialogController'
