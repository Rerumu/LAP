-- stream based Lua parser and error utilities module
local lex_next
local lex_keywords = {
	'and',
	'break',
	'do',
	'else',
	'elseif',
	'end',
	'false',
	'for',
	'function',
	'goto',
	'if',
	'in',
	'local',
	'nil',
	'not',
	'or',
	'repeat',
	'return',
	'then',
	'true',
	'until',
	'while',
}

local lex_symbols = {
	'"',
	'#',
	'%',
	'&',
	'(',
	')',
	'*',
	'+',
	',',
	'-',
	'--',
	'.',
	'..',
	'...',
	'/',
	'//',
	':',
	'::',
	';',
	'<',
	'<<',
	'<=',
	'=',
	'==',
	'>',
	'>=',
	'>>',
	'[',
	'\'',
	']',
	'^',
	'{',
	'|',
	'}',
	'~',
	'~=',
}

local lex_unary_bind_value = 22
local lex_unary_bind = {'#', '+', '-', '~', 'not'}
local lex_binary_bind = {
	{{1, 2}, {'or'}},
	{{3, 4}, {'and'}},
	{{5, 6}, {'<', '<=', '==', '>', '>=', '~='}},
	{{7, 8}, {'|'}},
	{{9, 10}, {'~'}},
	{{11, 12}, {'&'}},
	{{13, 14}, {'<<', '>>'}},
	{{16, 15}, {'..'}},
	{{17, 18}, {'+', '-'}},
	{{19, 20}, {'%', '*', '/', '//'}},
	{{24, 23}, {'^'}},
}

local lex_escapes = {
	['"'] = '"',
	['\''] = '\'',
	['\\'] = '\\',
	['\n'] = '\n',
	['a'] = '\a',
	['b'] = '\b',
	['f'] = '\f',
	['n'] = '\n',
	['r'] = '\r',
	['t'] = '\t',
	['v'] = '\v',
	['z'] = '\z',
}

for i = 1, #lex_unary_bind do
	lex_unary_bind[lex_unary_bind[i]] = lex_unary_bind_value
	lex_unary_bind[i] = nil
end

for i = 1, #lex_binary_bind do
	local v = lex_binary_bind[i]
	local t = {left = v[1][1], right = v[1][2]}
	lex_binary_bind[i] = nil

	for _, n in ipairs(v[2]) do lex_binary_bind[n] = t end
end

local function lex_syntax_error(ls, err, ...)
	local msg = string.format(err, ...)
	local name = ls.name or string.format('[string %q]', ls.src:sub(1, 12))
	local line = ls.line

	error(string.format('%s:%i: %s', name, line, msg), 0)
end

local function lex_test_next(ls, name)
	local ok = ls.token.name == name

	if ok then lex_next(ls) end

	return ok
end

local function lex_syntax_unexpected(ls, other)
	local sn = ls.token.slice or ls.token.name

	if other then
		lex_syntax_error(ls, 'unexpected `%s` (missing `%s`)', sn, other)
	else
		lex_syntax_error(ls, 'unexpected `%s`', sn)
	end
end

local function lex_syntax_expect(ls, name)
	if not lex_test_next(ls, name) then lex_syntax_unexpected(ls, name) end
end

local function lex_syntax_closes(ls, line, open, close)
	if not lex_test_next(ls, close) then
		if ls.line == line then
			lex_syntax_error(ls, 'no `%s` closing `%s`', close, open)
		else
			lex_syntax_error(ls, 'no `%s` closing `%s` (at line %i)', close, open, line)
		end
	end
end

local function lex_follows(ls)
	local nm = ls.token.name

	return nm == 'else' or nm == 'elseif' or nm == 'end' or nm == 'until' or nm == '<eos>'
end

local function lex_is_sep(ls, pos)
	local eq = ls.src:match('^%[(=*)%[', pos)
	local value = false

	if eq then value = #eq end

	return value
end

local function lex_str_line(ls, pos, line)
	local src = ls.src

	while true do
		local white = src:match('^[\r\n]', pos)

		if white == '\r' then
			if src:sub(pos + 1, pos + 1) == '\n' then pos = pos + 1 end
		elseif white ~= '\n' then
			break
		end

		pos = pos + 1
		line = line + 1
	end

	return pos, line
end

local function lex_skip_line(ls) ls.pos, ls.line = lex_str_line(ls, ls.pos, ls.line) end

local function lex_skip_white(ls)
	local src = ls.src
	local pos = ls.pos
	local white

	repeat
		white = src:match('^%s', pos)
		pos = pos + 1

		if white == '\r' or white == '\n' then white = nil end
	until white == nil

	ls.pos = pos - 1
end

local function lex_init_keyword(_, token)
	local slice = token.slice
	local name

	for i = #lex_keywords, 1, -1 do
		local k = lex_keywords[i]

		if slice == k then
			name = k
			break
		end
	end

	if name then
		token.name = name
		token.slice = nil
	end
end

local function lex_init_symbol(ls, token)
	local src = ls.src
	local pos = ls.pos
	local name

	for i = #lex_symbols, 1, -1 do
		local s = lex_symbols[i]
		local n = pos + #s

		if s == src:sub(pos, n - 1) then
			ls.pos = n
			name = s
			break
		end
	end

	if name then
		token.name = name
		token.slice = nil
	end

	return name ~= nil
end

local function lex_init_ident(ls, token)
	local _, e, ident = ls.src:find('^([%w_]+)', ls.pos)

	token.name = '<ident>'
	token.slice = ident
	ls.pos = e + 1
end

local function lex_init_numeric(ls, token)
	local _, e, num = ls.src:find('^([%x%.xX]*[eEpP]?[+-]?%x+)', ls.pos)
	local value = tonumber(num)
	local name

	if value == nil then lex_syntax_error(ls, 'malformed number') end

	if math.tointeger(value) then
		name = '<integer>'
	else
		name = '<number>'
	end

	ls.pos = e + 1
	token.name = name
	token.slice = num
end

local function lex_esc_hexadecimal(ls, pos)
	local _, e, num = ls.src:find('^(%x%x)', pos + 1)
	local esc

	if num then
		esc = string.char(tonumber(num))
	else
		lex_syntax_error(ls, 'should be 2 hexadecimal digits')
	end

	return e, esc
end

local function lex_esc_unicode(ls, pos)
	local _, e, num = ls.src:find('^{(%x+)}', pos + 1)
	local esc

	if num then
		num = tonumber(num, 16)

		if num < 0x11000 then
			esc = utf8.char(num)
		else
			lex_syntax_error(ls, '`%X` should be between 0 and 10FFF', num)
		end
	else
		lex_syntax_error(ls, 'should be hexadecimal digits')
	end

	return e, esc
end

local function lex_esc_decimal(ls, pos)
	local _, e, num = ls.src:find('(%d+)', pos)
	local esc
	num = tonumber(num)

	if num < 256 then
		esc = string.char(num)
	else
		lex_syntax_error(ls, '`%i` should be between 0 and 255', num)
	end

	return e, esc
end

local function lex_esc_special(ls, pos)
	local esc = lex_escapes[ls.src:sub(pos, pos)]

	if esc == nil then lex_syntax_error(ls, 'invalid escape sequence') end

	return pos, esc
end

local function lex_init_string(ls, token)
	local src, len = ls.src, #ls.src
	local line = ls.line
	local pos = ls.pos
	local quo = src:sub(pos, pos)
	local str = {}
	local lsc

	while pos <= len do
		pos = pos + 1
		lsc = src:sub(pos, pos)

		if lsc == '\\' then
			local esc

			pos = pos + 1
			lsc = src:sub(pos, pos)

			if lsc == 'x' then
				pos, esc = lex_esc_hexadecimal(ls, pos)
			elseif lsc == 'u' then
				pos, esc = lex_esc_unicode(ls, pos)
			elseif tonumber(lsc) then
				pos, esc = lex_esc_decimal(ls, pos)
			else
				pos, esc = lex_esc_special(ls, pos)
			end

			table.insert(str, esc)
		elseif lsc == '\r' or lsc == '\n' then
			pos, line = lex_str_line(ls, pos, line)
		elseif lsc == quo then
			pos = pos + 1
			break
		else
			table.insert(str, lsc)
		end
	end

	if lsc ~= quo then lex_syntax_error(ls, 'unfinished string') end

	ls.pos = pos
	ls.line = line
	token.name = '<string>'
	token.slice = table.concat(str)
end

local function lex_init_long_string(ls, token, sep)
	local src, len = ls.src, #ls.src
	local line = ls.line
	local stt = ls.pos + sep + 2
	local pos = stt
	local ok = false

	while pos <= len do
		local lsc = src:sub(pos, pos)

		if lsc == '\r' or lsc == '\n' then
			pos, line = lex_str_line(ls, pos, line)
		elseif lsc == ']' then
			local init = pos + 1
			for _ = 1, sep + 1 do
				pos = pos + 1
				lsc = src:sub(pos, pos)
				if lsc ~= '=' then break end
			end

			if lsc == ']' and (pos - init) == sep then
				pos = pos + 1
				ok = true
				break
			end
		else
			pos = pos + 1
		end
	end

	if not ok then lex_syntax_error(ls, 'unfinished long string') end

	ls.pos = pos
	ls.line = line
	token.name = '<string>'
	token.slice = src:sub(stt, pos - sep - 3)
end

local function lex_str_comment(ls)
	local src, len = ls.src, #ls.src
	local stt = ls.pos + 2
	local pos = stt

	while pos <= len do
		local lsc = src:sub(pos, pos)
		pos = pos + 1

		if lsc == '\r' or lsc == '\n' then break end
	end

	ls.pos = pos - 1
	return src:sub(stt, pos - 2)
end

function lex_next(ls)
	local token = {}
	local src = ls.src
	local pos

	while true do
		pos = ls.pos
		if src:find('^[\r\n]', pos) then -- newline
			lex_skip_line(ls)
		elseif src:find('^%s', pos) then -- whitespace
			lex_skip_white(ls)
		elseif src:find('^%-%-', pos) then -- comments
			local sep = lex_is_sep(ls, pos + 2)
			local cmt

			if sep then
				ls.pos = pos + 2
				lex_init_long_string(ls, token, sep)

				token.name = nil
				cmt = token.slice
			else
				cmt = lex_str_comment(ls)
			end

			table.insert(ls.comment, cmt)
		else
			break
		end
	end

	if src:find('^[%a_]', pos) then
		lex_init_ident(ls, token)
		lex_init_keyword(ls, token)
	elseif src:find('^%d', pos) then
		lex_init_numeric(ls, token)
	elseif src:find('^%p', pos) and lex_init_symbol(ls, token) then
		local name = token.name

		if name == '.' and src:find('^%d', pos + 1) then -- number
			ls.pos = ls.pos - 1
			lex_init_numeric(ls, token)
		elseif name == '"' or name == '\'' then -- string
			ls.pos = ls.pos - 1
			lex_init_string(ls, token)
		elseif name == '[' then -- long string
			local sep = lex_is_sep(ls, ls.pos - 1)

			if sep then
				ls.pos = ls.pos - 1
				lex_init_long_string(ls, token, sep)
			end
		end
	elseif pos > #src then
		token.name = '<eos>'
	else
		lex_syntax_unexpected(ls)
	end

	ls.token = token
end

return {
	binary_bind = lex_binary_bind,
	follows = lex_follows,
	next = lex_next,
	syntax_closes = lex_syntax_closes,
	syntax_error = lex_syntax_error,
	syntax_expect = lex_syntax_expect,
	syntax_unexpected = lex_syntax_unexpected,
	test_next = lex_test_next,
	unary_bind = lex_unary_bind,
	unary_bind_value = lex_unary_bind_value,
}
