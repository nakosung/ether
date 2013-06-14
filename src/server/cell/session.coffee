# add session-support onto cell server/client
_ = require 'underscore'
async = require 'async'
events = require 'events'
grace = require '../grace'

module.exports = 
	server : (tissueServer) ->
		tissueServer?.on 'cell', (cell) ->
			cell.on 'node', (node) ->			
				sessions = {}
				node.once 'close', ->
					jobs = _.keys(sessions).map (k) => (cb) => leave k, cb
					async.parallel jobs, ->

				join = (session,cb) ->
					class Session extends events.EventEmitter
						constructor : (@node) ->
							@id = session						
							@methods = {}
							@node.emit 'session', @

						destroy : (cb) ->									
							if @emit 'shutdown'
								@once 'close', cb
							else
								delete sessions[session]
								@emit 'close'
								@removeAllListeners()
								cb()

						invoke : (args...) -> grace.invoke.call @, args...
						invoke_remote : (args...,cb) -> node.invoke_remote @id, args..., cb

					return cb('already joined') if sessions[session]
					guest = sessions[session] = new Session node

				leave = (session,cb) ->
					return cb('not joined') unless sessions[session]
					sessions[session].destroy(cb)

				invoke = (method,session,args...,cb) ->					
					guest = sessions[session]
					return cb('invalid guest:'+session) unless guest
					guest.invoke(method,args...,cb)

				node.once 'close', => destroy()
				node.methods['+session'] = (session,cb) => join(session,cb)
				node.methods['-session'] = (session,cb) => leave(session,cb)
				node.methods['*'] = (args...,cb) => invoke(args...,cb)

	# Client-aware cell excluding RPC stuff
	client : (tissueClient) ->
		tissueClient.on 'cell', (cell) ->			
			sessions = {}
			numSessions = 0			

			cell.methods['*'] = (session,args...,cb) ->
				agent = sessions[session]
				return cb('invalid session') unless agent
				agent.invoke args..., cb

			cell.once 'shutdown', ->
				jobs = []
				for k,v of @sessions
					jobs.push (cb) => v.leave(cb)
				
				async.parallel jobs, -> cell.emit 'close'			

			cell.join = (session,cb) ->
				id = session.id
				return cb('already open') if sessions[id] 				

				class Agent extends events.EventEmitter
					constructor : (@session) ->				
						@id = id	
						@methods = {}
						fnSessionCloseHandler = => @leave =>

						# TO ENSURE HARD PAIRING!
						sessions[id] = @
						@session.once 'close', fnSessionCloseHandler

						if numSessions++ == 0
							cell.activate()

						add = => 
							@emit 'online', @
							cell.invoke_remote '+session', id, ->
						remove = =>
							cell.invoke_remote '-session', id, ->
							@emit 'offline', @
						
						# To ensure other listeners receiving 'online' signal properly, we should defer calling add()
						if cell.is_online() 
							process.nextTick => add()

						cell.on 'online', add
						cell.on 'offline', remove

						@on 'close', =>
							cell.removeListener 'online', add
							cell.removeListener 'offline', remove

							if cell.is_online()
								remove()

							delete sessions[id]
							@session.removeListener 'close', fnSessionCloseHandler
							if --numSessions == 0
								console.log 'all sessions dropped from cell client'
								cell.deactivate()

					leave : (cb) ->
						@emit 'close'
						@removeAllListeners()

					invoke_remote : (method,args...,cb) ->
						cell.invoke_remote method, session.id, args..., cb

					invoke : (args...) ->
						grace.invoke.call(@,args...)

				agent = new Agent(session)			
				cell.emit 'session', agent

				cb()