{exec}  = require 'child_process'
{spawn} = require 'child_process'
prelude = require 'prelude-ls'
request = require 'request'
xml2js  = require 'xml2js'
async   = require 'async'
path    = require 'path'
temp    = require 'temp'
util    = require 'util'
cli     = require 'nomnom'
url     = require 'url'
fs      = require 'fs'
reader  = require 'line-reader'

global import prelude

# = CLI ============================================================== CLI = #

# -------------------------------------------------------------------------- #

let @ = cli.nocolors!

	@script 'dezoomify'

	@option 'version',
		abbr: 'V'
		flag: true
		help: 'print version and exit'
		callback: -> "v0.0.1"

# -------------------------------------------------------------------------- #

let @ = cli.command 'scrape'

	@option 'path',
		help: 'Test file to run'
		list: true
		required: true
		position: 1

	@option 'base',
		abbr: 'b'
		help: 'testing'

	@option 'verbose',
		abbr: 'v'
		help: 'be verbose'

	@callback (opts) ->
		console.log opts

# -------------------------------------------------------------------------- #

let @ = cli.command 'path'

	@option 'path',
		help: 'Test file to run'
		list: true
		required: true
		position: 1

	@option 'output',
		abbr: 'o'
		help: 'output file'
		required: true

	@option 'base',
		abbr: 'b'
		help: 'testing'

	@option 'verbose',
		abbr: 'v'
		help: 'be verbose'

	@callback (o) ->
		paths = o.path.map (f) -> if o.base then url.resolve o.base, f else f
		for path in paths
			parsed = url.parse path
			if !parsed.host
			or !parsed.protocol
			or  parsed.protocol not in <[ http: https: ]>
				console.error 'Invalid URL: ' + path
			else
				xml_queue.push { path, output: o.output }


let @ = cli.command 'file'

	@option 'file',
		help: 'File to read'
		required: true
		position: 1

	@option 'base',
		abbr: 'b'
		help: 'prepend base URL'

	@option 'output',
		abbr: 'o'
		help: 'Base output'

	@option 'start',
		abbr: 's'
		help: 'Start index'

	@option 'last',
		abbr: 'l'
		help: 'Last index'

	@option 'skip',
		help: 'Skip already done'
		flag: true

	@callback (o) ->
		i = 0
		s = (parse-int o.start) || 0
		l = (parse-int o.last) || false
		reader.eachLine o.file, (line, end, done) ->
			i++
			[inp, outp] = line.split ','
			input  = url.resolve (o.base || ''), inp
			output = path.join (o.output || __dirname), outp
			if o.skip and fs.exists-sync output
				console.log 'Skip: '.magenta + i + ': ' + outp
				done!
			else if i >= s and (!l or i <= l)
				exec "lsc dezoomify path #input -o #output", (err, stdout, stderr) ->
					console.log 
					if err or stderr then console.error 'Error: '.red + i + ': ' + outp
					else console.log 'Okay: '.green + i + ': ' + outp
					if end then done false else done!
			else if l and i > l then done false
			else done!
			
# ========================================================================== #

xml_queue = async.queue !({ path, output }, callback) ->
	temp.cleanup!
	xml_url = url.resolve path, 'ImageProperties.xml'
	console.log ' GET '.magenta + ' ' + xml_url
	request xml_url, !(err, res, body) ->
		if err or !body
			console.error 'ERR '.red + xml_url
			callback!
		else
			console.log (' '+res.status-code+' ').green + ' ' + xml_url

			if res.status-code.to-string![0] is '2'

				xml2js.parse-string body.to-lower-case!, (err, json) ->
					if err or !json
						console.log 'fail'
						callback!
					else
						{ width, height, tilesize } = json?['image_properties']?['$']

						cols = Math.ceil width  / tilesize
						rows = Math.ceil height / tilesize
						zoom = 0

						w = width
						h = height
						tile_counts = []
						while w > tilesize or h > tilesize
							zoom++

							w = Math.floor w / 2
							h = Math.floor h / 2

							t_wide = Math.ceil w / tilesize
							t_high = Math.ceil h / tilesize
							tile_counts.unshift t_wide * t_high

						tile_counts.unshift 1
						tile_count_before_level = sum tile_counts[1 to -1]
						tcbl = tile_count_before_level

						files_by_row = []

						async.map [0 to rows-1], (y, callback) ->
							async.map [0 to cols-1] (x, callback) ->
								tile_group = Math.floor (x + y * cols + tcbl) / tilesize

								resource = url.resolve path,
									"TileGroup#tile_group/#zoom-#x-#y.jpg"

								tile_queue.push { resource, 1 }, (err, data) ->
									callback null, data
							, (err, data) ->
								# a bit of a hack to make sure file gets cleaned up on exit
								file = temp.open-sync 'dezoomify-row'
								fs.close-sync file.fd
								fs.unlink-sync file.path
								###
								cmd = "gm montage -gravity NorthWest -tile #{data.length}x1 -geometry +0+0 #{data[0 to -1].join ' '} jpg:#{file.path}"

								exec cmd, (err, stdout, stderr) ->
									callback null, file.path

						, (err, data) ->
							cmd = "gm montage -gravity NorthWest -tile 1x#{data.length} -geometry +0+0 #{data[0 to -1].join ' '} #{output}"

							exec cmd, (err, stdout, stderr) ->
								if err then callback new Error 'Uhoh'
								else callback output

			else
				console.error "#{' ERR '.red.inverse} #{xml_url}"
				callback!

# ========================================================================== #

tile_queue = async.queue !({ resource, index }, callback) ->
	console.log " #{'GET'.magenta} #{resource}"
	request resource, encoding: null, (err, res, data) ->
		if err
			console.error "#{' ERR '.red.inverse} #{resource}"
			callback err
		else
			status = res.status-code.to-string!
			s-type = status[0]
			c-type = res.headers?['content-type']
			format = (c-type.split '/')[0]

			if s-type is '2'
				if format is 'image'
					try
						stream = temp.create-write-stream 'dezoomify-tile'
						stream.write data
						stream.end!
						console.log " #{status.green} #{resource}"
						# was leaving blank spaces so maybe waiting will help
						setTimeout ->
							callback null, stream.path
						, 10
					catch e
						console.error "#{' ERR '.red.inverse} #{resource}"
						callback e
				else
					console.error "#{' ERR '.red.inverse} #{resource}"
					callback new Error 'Not an image.'
			else
				console.error " #{(' '+status+' ').red.inverse} #{resource}"
				callback new Error 'Error'
, 15

# ========================================================================== #

cli.parse!

process.on 'SIGINT', ->
	console.log "\nGracefully shutting down..."
	process.exit!
