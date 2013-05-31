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
				files: 'lib/**/*.coffee'
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
				cwd:'lib'
				src:['**/*.coffee']
				dest:'build/'
				ext:'.js'
		shell:
			browserify:
				command: 'browserify build/client/app.js -o public/lib/bundle.js'
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
		
	grunt.registerTask 'client', ['coffee:client','shell:browserify']	
	grunt.registerTask 'shared', ['coffee:shared','shell:browserify']
	grunt.registerTask 'test', ['mochaTest']
	grunt.registerTask 'server', ['coffee:server']
	grunt.registerTask 'default', ['shell:run','watch']

	# watching server folder
	