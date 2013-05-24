async = require 'async'


jobs = [1..100].map (x) -> 
	(cb) -> 
		setTimeout (->
			console.log x
			cb()
			), Math.random() * 1000 + 500
		

async.parallel jobs, ->
	console.log 'done'
	