ether = require '../src/server/ether'
{EventEmitter} = require 'events'
_ = require 'underscore'
async = require 'async'

test_config = ->
	class TestClass
		constructor : (@cell) ->
		init : (cb) ->
			cb()
		destroy : (cb) ->
			cb()		

	config = 
		user_class : TestClass
		id : (x) -> "MochaMembrane:#{x}"
		swapout_delay : 1000

describe 'Membrane', ->
	server = ether [], id:'mocha', dir:'.'	
	{Membrane} = server.use 'cell/membrane'	

	describe 'simple case', ->		
		config = test_config()

		it 'should open and release', (done) ->		
			membrane = new Membrane(config)
			async.series [
				(cb) -> membrane.open "ABC", cb
				(cb) -> membrane.release cb
			], done

		it 'should open and release with emitting appropriate event', (done) ->				
			count = 3
			fn = -> done() if --count == 0

			membrane = new Membrane(config)
			membrane.once 'open', fn				
			membrane.once 'close', fn
			async.series [
				(cb) -> membrane.open "ABC", cb
				(cb) -> membrane.release cb
			], fn

		describe 'multiplayer', ->			
			a = b = null
			beforeEach (done) ->
				a = new Membrane(config)

				other_server = ether [], id:'mocha-other', dir:'.'	
				module = other_server.use 'cell/membrane'	

				b = new module.Membrane(config)
				a.open "ABC", done

			afterEach (done) ->
				a.release done
				a = b = null				

			it 'should get along with friends', (done) ->			
				async.series [					
					(cb) -> b.open "DEF", cb					
					(cb) -> b.release cb
				], done

			it 'should not interfere friends', (done) ->						
				b.open "ABC", (err) ->
					err.should.not.eql(null)
					done()

		describe 'swapout', ->
			it 'should swap out', (done) ->
				c = _.extend config, swapout_delay : 10
				a = new Membrane(c)
				a.on 'close', done
				async.series [
					(cb) -> a.open 'ABC', cb
					(cb) -> 
						a.sub()
						a.unsub()						
				], ->


describe 'NervTissue', ->
	server = null
	client = null
	TissueClient = null
	config = null

	class CellClient
		constructor : (@tissue,@config,@cell) ->			

		set_connection : (connection) ->			
			@connection = connection
			if connection
				if connection.is_online()
					@init_net()				
				else
					connection.once 'open', =>
						@init_net()

		init_net : ->

	beforeEach (done) ->
		mother = ether [], id:'mocha', dir:'.'	
		{Membrane} = mother.use 'cell/membrane'				
		{TissueServer,TissueClient} = mother.use 'cell/nervtissue'	
		config = test_config()
		config.Membrane = Membrane
		config.swapout_delay = 100
		config.client_class = CellClient
		server = new TissueServer config
		server.init done

	afterEach (done) ->		
		server.shutdown done

	describe 'server', ->
		it 'should open new membrane!', (done) ->
			cell = 'TissueABC'
			server.on 'add', (new_cell) ->
				cell.should.eql new_cell
				done()
			server.replyToClientSub cell

		it 'should close unnecessary membrane!', (done) ->
			cell = 'TissueABC'
			server.on 'remove', (removed_cell) ->
				cell.should.eql removed_cell
				done()
			server.replyToClientSub cell
			server.replyToClientUnsub cell

		it 'should close unnecessary membrane!', (done) ->
			cell = 'TissueABC'
			server.on 'remove', (removed_cell) ->
				cell.should.eql removed_cell
				done()
			server.replyToClientSub cell
			server.replyToClientSub cell
			server.replyToClientUnsub cell
			server.replyToClientUnsub cell

	describe 'client', ->
		beforeEach (done) ->
			client = new TissueClient config
			client.init(done)
		afterEach ->
			client.shutdown()

		it 'should pass', ->
			cell_id = 'ABC'
			cell = client.cell cell_id			
			client.activate cell_id
			client.deactivate cell_id

		it 'should host a cell during lifecycle', (done) ->
			cell_id = 'ComplexABC'
			cell = client.cell cell_id

			server.on 'add', (new_cell) ->				
				cell_id.should.eql new_cell
				client.deactivate cell_id
			server.on 'remove', (removed_cell) ->				
				cell_id.should.eql removed_cell
				done()

			client.activate cell_id

		describe 'multi-client', ->
			client2 = null
			beforeEach (done) ->
				client2 = new TissueClient config
				client2.init(done)
			afterEach ->
				client2.shutdown()

			it 'should pass', (done) ->
				cell_id = 'ComplexABC'
				cell = client.cell cell_id

				alive = false
				c1 = c2 = false

				check = ->
					if alive
						if c1
							c1 = false
							client.deactivate cell_id
						if c2
							c2 = false
							client2.deactivate cell_id

				server.on 'add', (new_cell) ->				
					cell_id.should.eql new_cell
					alive = true					
					check()
				server.on 'remove', (removed_cell) ->				
					cell_id.should.eql removed_cell
					done()

				client.activate cell_id
				c1 = true
				check()
				
				client2.activate cell_id
				c2 = true
				check()