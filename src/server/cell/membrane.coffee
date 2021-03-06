async = require 'async'
events = require 'events'
grace = require '../grace'
assert = require 'assert'

module.exports = (server) ->
	server.use 'token'
	# Membrane holds 'cell' with 'token'.
	# Holding cell is managed by typical node.js style life-cycle.
	# eg)
	#		blahblah.on 'cell', (cell) ->
	#			### your ctor here ###
	#			cell.on 'close', ->
	#				### your dtor here ###
	#			### all of your logic here ###	
	#
	# If membrane lose its token, it handles graceful-shutdown and migration.

	# Membrane should host arbtrary type of cells, including dedicated commercial game engines like UnrealEngine dedicated server.
	# In that case, cell would provide access point and auth between user and dedicated server.

	# open/release
	class Membrane extends events.EventEmitter
		constructor : (@config) ->

		toString : -> 
			assert(@token)
			@token

		# public interface
		open : (cell,cb) ->
			@token = @config.id(cell)			

			fn = (taker,cb) =>
				#console.log 'take!!!', taker
				return cb('no way') unless taker == "TIMEOUT" or not taker? # null taker is DESTROYER!

				@destroy(cb)
						
			#console.log 'server request'.bold.red, server.id, @token
			async.series [
				(cb) => server.acquireToken server.id, @token, fn, cb
				(cb) => @init cell, cb
			], cb

		# public interface
		release : (cb) ->
			server.destroyToken @token, cb

		sub : ->
			@clients++
			@clear_swapout()			

		unsub : -> 
			@swapout() if --@clients == 0
				

		# private interface begins
		init : (cell,cb) ->			
			@clients = 0			
			@emit 'open'
			cb()

		# caution : this function should not be invoked with having token.
		destroy : (cb) ->
			@clear_swapout()
			grace.shutdown.call @, cb

		swapout : ->
			# if already swapout is scheduled, skip it
			return if @swappingout

			fnSwapout = =>			
				# release this cell
				@release =>
					# there is no more scheduled swapping out. :)
					@swappingout = null

			# delayed swapping-put
			timeout = setTimeout fnSwapout, @config.swapout_delay

			# to cancel scheduled swap-out, we maintain 'cancel' fn.
			@swappingout = -> clearTimeout timeout

		clear_swapout : ->
			# if there is a scheduled swap-out, call it to discard.
			@swappingout?()
			@swappingout = null		

	Membrane:Membrane