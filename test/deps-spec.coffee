deps = require '../lib/deps'
ether = require '../lib/ether'
{EventEmitter} = require 'events'
_ = require 'underscore'
async = require 'async'
cluster = require 'cluster'

describe 'Deps', ->
	describe 'standalone', ->
		server = ether ['deps'], id:'mocha', dir:'../lib'	
		
		X = server.deps

		describe 'basic', ->
			it 'should write and emit', (done) ->
				keys = 'hello world'.split(' ')

				server.once 'dep:update', (written) ->
					(_.difference _.keys(written), keys).should.eql []			
					(_.without _.flatten(_.values(written)), '1').should.eql []
					done()

				keys.forEach (k) -> X.write k, '1'
				
			it 'should aggregate', (done) ->
				keys = 'hello world'.split(' ')

				server.once 'dep:update', (written) ->
					written.should.eql {aggr:keys}
					done()

				keys.forEach (k) -> X.write 'aggr', k

		describe 'watch', ->
			W = null

			afterEach ->
				W.destroy()
				W = null

			it 'should watch', (done) ->
				W = X.watch done
				W.begin()
				X.read 'hello', '1'
				W.end()
				X.write 'hello', '2' # it should not fire fn
				X.write 'hello', '1'

			it 'should be able to change watch targets', (done) ->
				W = X.watch done
				W.begin()
				X.read 'hello', '1'
				W.end()			

				W.begin()
				X.read 'world', '*'
				W.end()

				X.write 'hello', '1'
				X.write 'world', '2'				

	describe 'cluster', ->
		server = null
		worker = null
		X = null

		before (done) ->			
			server = ether ['cluster', 'deps'], id:'mocha', dir:'../lib'

			(server.deps?).should.be.true
			X = server.deps

			async.parallel [
				(cb) -> server.initialize cb
				(cb) -> worker = require('./cluster/master') 'deps-slave', cb					
			], done

		after (done) ->			
			async.parallel [
				(cb) -> server.exit cb
				(cb) -> worker.terminate cb
			], done					

		it 'should watch within cluster', (done) ->
			async.parallel [
				(cb) -> 
					W = X.watch cb
					W.begin()
					X.read 'remote', '*'
					W.end()
				(cb) -> worker.rpc 'write','remote','2', cb		
			], done	