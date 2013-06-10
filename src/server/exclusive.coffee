# Exclusive provides 'weak mutex'.
# Concept of 'Weak mutex' is providing way to migrate ownership. Instead of just waiting mutex to be released, 
# agents can ask owner to migrate its ownership to them. Of course, owner can reject the request.

# There are only two methods for simple API
#	take : (token, user-fn, args..., callback)
#		user-fn is called when others are asking to migrate ownership with just the same arguments as asked.
#		eg) A.take 'x', fn, 1, 2, 3, cb ==> OK!
#			B.take 'x', fn2, 'a', 'b', cb ==> fn is called with ['a','b']
#		user-fn can reject by error-back.
#	
#		* IMPORTANT * user-fn can *NOT* deny ['TIMEOUT']
#
#	destroy : (token,args...,callback)
#		In case of just wanting mutex to be off, we can call destroy instead of take. :)

# This functionality is backed by redis.

_ = require 'underscore'
redis = require 'redis'
async = require 'async'

# server should respond in one sec, or you can lose it!
TIMEOUT = 1000

class Exclusive
	constructor : (@opt) ->		
		@id = @opt.id ? (Math.random() * 1000000).toString(36)

		@pub = @opt.pub or redis.createClient()
		@sub = @opt.sub or redis.createClient()

		@sub.subscribe 'token:call'
		@sub.subscribe 'token:back'

		@pending = {}
		@nextId = 0

		@haves = {}

		@sub.on 'message', (channel,message) =>
			# if require('cluster').isMaster
			# 	console.log 'MASTER', channel, message
			# else
			# 	console.log 'SLAVE', channel, message
			return unless /^token:/.test(channel)

			switch channel
				when 'token:call' 
					[token,id,caller,args...] = JSON.parse(message)
					if id != @id and @haves[token]? 	
						@haves[token] args..., (err,args...) =>
							delete @haves[token] unless err
							if args[0] == "TIMEOUT"
								console.warn "exclusive:TIMEOUT DETECTED".bold, token, id, caller
							@pub.publish 'token:back', JSON.stringify([id,caller,err,args...])
						
				when 'token:back'
					[id,caller,args...] = JSON.parse(message)					
					if id == @id 
						pending = @pending[caller]						
						if pending?.cb
							clearTimeout(pending.timeout)
							delete @pending[caller]	
							pending.cb(args...)

		#process.on 'exit', =>
			#console.log "EXITEXITEXITEXITEXIT".red.bold

	read : (token,cb) ->
		key = 'xc:' + token
		async.waterfall [
			(cb) => @pub.get key, cb,
			(result,cb) =>
				if result
					[id,args...] = result.split(':')
					r = 
						id:id
						args:args
					cb(null,r)
				else
					cb()
		], cb
		
	take : (token,fn,args...,cb) ->
		throw new Error('cb!') unless _.isFunction(cb)
		throw new Error('token should be not null') unless token
		throw new Error('you cannot pass fn as arg') if _.any args, _.isFunction

		# all arguments are stringified first
		args = args.map String

		# key, value for redis
		key = 'xc:' + token
		value = [@id,args...].join(':')

		#console.log 'take'.bold, 'begin', token, args

		repeat = =>
			async.waterfall [
				(cb) =>					
					# is it local?
					if @haves[token]?
						#console.log 'i have the token', args
						@haves[token] args..., cb
					else
						# mark we will have this! (so there are more than one node responding to this token)
						@haves[token] = (args...,cb) -> cb('BUSY')

						async.waterfall [
							# is it owned?
							(cb) => @pub.setnx key, value, cb
							(result,cb) =>
								# nobody has it, so it is ours now!
								if result == 1
									cb()
								else
									# ask owner
									caller = @nextId++									

									# owner may be down or past away.									'
									timeout = setTimeout (=> 
										@pub.publish 'token:call', JSON.stringify([token,@id,caller,"TIMEOUT"])
										cb()
									), TIMEOUT

									@pending[caller] = timeout:timeout,cb:cb
									@pub.publish 'token:call', JSON.stringify([token,@id,caller,args...])
						], (err,result) =>
							if err
								delete @haves[token]
							cb(err,result)
				(a...,cb) =>
					#console.log 'take'.bold, 'end'.red, token, args

					# are we claiming this ticket?
					if fn
						@haves[token] = fn
						@pub.set key, value, cb
					# or just need to clear this one
					else
						delete @haves[token]
						@pub.del key, cb
			], (err) =>				
				#console.log err
				if err == 'BUSY'					
					setTimeout (=> repeat()), 200
				else
					cb(err)

		repeat()
			

	destroy : (token,args...,cb) ->
		#console.log 'destroy'.green.bold,args
		@take token,null,args...,cb

module.exports = (opt) ->
	new Exclusive(opt)
