module.exports = (server) ->
	server.use 'rpc'

	# cell can be a room in chat service, a zone in mmorpg world, and so on.
	# cell should be contained in one thread which is running on one node app.
	# this will eliminate all kinds of dirties related with concurrency.

	# all cells of a kind are homogeneous.

	class Cell
		constructor : ->
			@server = null

	class Consumer
		constructor : ->
			@cells = {}

