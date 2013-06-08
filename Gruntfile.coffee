module.exports = (grunt) ->
	grunt.initConfig
		watch:
			client:
				files: 'src/client/*.coffee'
				tasks: ['client']
				options:
					interrupt:yes
			shared:
				files: 'src/shared/*.coffee'
				tasks: ['shared']
				options:
					interrupt:yes
			server:
				files: 'src/server/*.coffee'
				tasks: ['server']				
				options:
					interrupt:yes
		coffee:
			shared:
				options:
					bare:yes
					sourceMap:true
				expand:true
				cwd:'src'
				src:['shared/*.coffee']
				dest:'build/'
				ext:'.js'
			client:
				options:
					bare:yes
					sourceMap:true
				expand:true
				cwd:'src'
				src:['client/*.coffee']
				dest:'build/'
				ext:'.js'
			server:
				options:
					bare:yes
					sourceMap:true
				expand:true
				cwd:'src'
				src:['server/*.coffee']
				dest:'build/'
				ext:'.js'
		shell:
			browserify:
				command: 'browserify -d build/client/app.js -o build/public/bundle.js'
				#command: "browserify -d -t coffeeify src/client/app.coffee -o public/lib/bundle.js"
				options:
					stdout:true
					stderr:true
					failOnError:true
			run:
				command: 'nodemon index.js'
				options:
					stdout:true
					stderr:true
					failOnError:true
					async:true
			test : 
				command: 'mocha --compilers coffee:coffee-script -r should -w'
				options:
					stdout:true
					stderr:true
					failOnError:true				
		uglify:
			build:
				src:'public/lib/bundle.js'
				dest:'public/lib/bundle.min.js'
		mochaTest:
			all : ['test/**/*.*']		


	grunt.loadNpmTasks 'grunt-contrib-watch'	
	grunt.loadNpmTasks 'grunt-contrib-coffee'	
	grunt.loadNpmTasks 'grunt-contrib-uglify'
	grunt.loadNpmTasks 'grunt-mocha-test'
	grunt.loadNpmTasks 'grunt-shell-spawn'

	grunt.registerTask 'mkdir_build', ->
		grunt.file.mkdir 'build/public'
		
	grunt.registerTask 'client', ['coffee:client','mkdir_build','shell:browserify']	
	grunt.registerTask 'shared', ['coffee:shared','client']
	grunt.registerTask 'test', ['shell:test']
	grunt.registerTask 'server', ['coffee:server']
	grunt.registerTask 'default', ['make','shell:run','watch']
	grunt.registerTask 'make', ['shared','server','client']

	# watching server folder
	