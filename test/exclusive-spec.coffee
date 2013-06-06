exclusive = require '../src/server/exclusive'
async = require 'async'

describe 'Exclusive', ->
	X = null
	before ->		
		X = exclusive id:'mocha'
	after ->		
		X = null	

	describe 'basic', ->
		it 'takes and destroy nicely', (done) ->
			fn = (arg,cb) ->				
				arg.should.equal('two')
				cb()			
			async.series [
				(cb) -> X.take 'test', fn, 'one', cb				
				(cb) -> X.destroy 'test', 'two', cb				
			], done

	describe 'exceptions', ->
		it 'should throw exception when function passed as an argument', ->
			fn = ->
				X.destroy 'anything', (->), (->)
			fn.should.throw()

	describe 'two participants', ->
		it 'yields nicely', (done) ->	
			semaphore = 2

			fn = (arg,cb) ->
				semaphore -= 1
				arg.should.equal('two')
				cb()

			fn2 = (arg,cb) ->
				semaphore -= 1
				arg.should.equal('three')
				cb()

			async.series [
				(cb) -> X.take 'test', fn, 'one', cb
				(cb) -> X.take 'test', fn2, 'two', cb
				(cb) -> X.destroy 'test', 'three', cb
				(cb) ->
					semaphore.should.equal(0)
					cb()
			], done

		it 'can reject on its own decision', (done) ->
			semaphore = 2

			fn = (arg,cb) ->				
				if arg == 'two'
					semaphore -= 1
					cb()
				else
					cb('NOWAY')

			fn2 = (arg,cb) ->
				semaphore -= 1
				arg.should.equal('three')
				cb()

			async.series [
				(cb) -> X.take 'test', fn, 'one', cb
				(cb) -> X.take 'test', fn2, 'errorsome', (err) ->
					(err == "NOWAY").should.be.true
					cb()
				(cb) -> X.take 'test', fn2, 'two', cb
				(cb) -> X.destroy 'test', 'three', cb
				(cb) ->
					semaphore.should.equal(0)
					cb()
			], done

	describe 'cluster', ->
		beforeEach (done) ->
			X.destroy 'test', 'force', done		

		it 'should work within a cluster', (done) ->
			fn_pass = null
			fn = (arg,cb) ->								
				if arg == 'two'					
					cb()
					fn_pass()
				else
					cb('NOWAY')

			worker = null

			async.series [
				(cb) -> X.take 'test', fn, 'one', cb
				(cb) ->					
					async.parallel [
						(cb) -> fn_pass = cb
						(cb) -> 
							worker = require('./cluster/master') 'exclusive-slave', cb
					], cb					
				(cb) -> worker.terminate cb
			], done

		after ->

