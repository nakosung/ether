require('coffee-script')

process.once('message',function(msg){
	var args = JSON.parse(msg)
	try {
		var r = require('./'+args[0]);		
		r(args.splice(1))
	} catch (e) {		
		process.send({result:e.error});
	}

	process.on('message',function(msg){		
		if (msg == 'force kill') {
			process.exit();
		}
	})

})





