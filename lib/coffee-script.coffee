fs = require 'fs'
path = require('path')
child_process = require 'child_process'
cluster = require 'cluster'

module.exports = (server) ->	
	server.installCompiler = ->
		console.log 'coffee-script: init'.green.bold
		src = @dir + '/src/client'
		out = @dir + '/lib/client'		
		
		cw = path.dirname(fs.realpathSync(__filename)) + '/..'

		cmd = cw + '/node_modules/coffee-script/bin/coffee'
		args = "-o #{out} -cw #{src}".split(' ')		

		p = child_process.fork cmd, args
		process.on 'exit', -> 
			console.log 'process exit'
			p.kill()

	server.installCompiler() unless cluster.worker?.id > 1