exclusive = require '../../lib/exclusive'
async = require 'async'
cluster = require 'cluster'

module.exports = (test) ->		
	X = exclusive id:'mocha-slave'
	fn = (arg,cb) ->
		console.log 'slave fn', arg
		cb()
	
	async.series [
		(cb) -> X.take 'test', fn, 'three', (err) ->
			unless err
				process.send result:['three']
				process.exit()
			else
				cb()
		(cb) -> X.take 'test', fn, 'two', cb		
	], (args...) ->		
		process.send result:[args...]