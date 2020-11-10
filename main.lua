local flags = {}
local show_error

do -- prepare program
	local usage = {}
	local info = {
		{'help', 'Show the help message and exit'},
		-- {'minify', 'Trim extra whitespace'},
		-- {'beautify', 'Format the code'},
		{'fold', 'Fold constant statements'},
		-- {'small', 'Minify the variable names'},
		-- {'smaller', 'Minify the variable names based on scoping'},
		-- {'pretty', 'Beautify the variable names'},
	}

	for _, flag in ipairs(info) do
		local name = flag[1]

		flags[name] = false
		table.insert(usage, string.format('\t--%-10s@ %s', name, flag[2]))
	end

	function show_error(err)
		error(err .. '\nusage: [options] inputs > output\n' .. table.concat(usage, '\n'), 0)
	end
end

local files = {}

do -- process command line arguments
	local args = {...}

	local function read_flag(str)
		if flags[str] == nil then
			show_error('unrecognized option `' .. str .. '`')
		else
			flags[str] = true
		end
	end

	for _, arg in ipairs(args) do
		if arg:sub(1, 2) == '--' then
			read_flag(arg:sub(3))
		else
			table.insert(files, arg)
		end
	end

	if flags.help then
		show_error('showing help')
	elseif #files == 0 then
		show_error('no input files provided')
	end
end

local source

do -- read files
	local sources = {}

	for _, name in ipairs(files) do
		local handle, err = io.open(name, 'rb')

		if not handle then
			show_error(err)
		else
			table.insert(sources, handle:read('*all'))
		end

		handle:close()
	end

	source = table.concat(sources, '\n')
end

do -- run program
	local LARPP = require('LARPP')
	local fold_const = require('tools.fold_const')
	local to_string = require('tools.to_string')

	local ast = LARPP.src2ast(source)

	if flags.fold then ast = fold_const(ast) end

	print(to_string(ast))
end
