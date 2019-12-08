-- stream based Lua parser and error utilities module
local luaX_next
local luaX_keywords = {
	'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'goto', 'if', 'in',
		'local', 'nil', 'not', 'or', 'repeat', 'return', 'then', 'true', 'until', 'while',
}

local luaX_symbols = {
	'"', '#', '%', '&', '(', ')', '*', '+', ',', '-', '--', '.', '..', '...', '/', '//', ':', '::',
		';', '<', '<<', '<=', '=', '==', '>', '>=', '>>', '[', '\'', ']', '^', '{', '|', '}', '~', '~=',
}

local luaX_unary_pvalue = 12
local luaX_unary_p = {'#', '+', '-', '~', 'not'}
local luaX_binary_p = {
	{{1, 1}, {'or'}}, {{2, 2}, {'and'}}, {{3, 3}, {'<', '<=', '==', '>', '>=', '~='}}, {{4, 4}, {'|'}},
		{{5, 5}, {'~'}}, {{6, 6}, {'&'}}, {{7, 7}, {'<<', '>>'}}, {{9, 8}, {'..'}},
		{{10, 10}, {'+', '-'}}, {{11, 11}, {'%', '*', '/', '//'}}, {{14, 13}, {'^'}},
}

local luaX_escapes = {
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

for i = 1, #luaX_unary_p do
	luaX_unary_p[luaX_unary_p[i]] = luaX_unary_pvalue
	luaX_unary_p[i] = nil
end

for i = 1, #luaX_binary_p do
	local v = luaX_binary_p[i]
	local t = {left = v[1][1], right = v[1][2]}
	luaX_binary_p[i] = nil

	for _, n in ipairs(v[2]) do
		luaX_binary_p[n] = t
	end
end

local function luaX_syntax_error(ls, err, ...)
	local msg = string.format(err, ...)
	local name = ls.name or string.format('[string %q]', ls.src:sub(1, 12))
	local line = ls.line

	error(string.format('%s:%i: %s', name, line, msg), 0)
end

local function luaX_test_next(ls, name)
	local ok = ls.token.name == name

	if ok then
		luaX_next(ls)
	end

	return ok
end

local function luaX_syntax_unexpected(ls, other)
	local sn = ls.token.slice or ls.token.name

	if other then
		luaX_syntax_error(ls, 'unexpected `%s` (missing `%s`)', sn, other)
	else
		luaX_syntax_error(ls, 'unexpected `%s`', sn)
	end
end

local function luaX_syntax_expect(ls, name)
	if not luaX_test_next(ls, name) then
		luaX_syntax_unexpected(ls, name)
	end
end

local function luaX_syntax_closes(ls, line, open, close)
	if not luaX_test_next(ls, close) then
		if ls.line == line then
			luaX_syntax_error(ls, 'no `%s` closing `%s`', close, open)
		else
			luaX_syntax_error(ls, 'no `%s` closing `%s` (at line %i)', close, open, line)
		end
	end
end

local function luaX_follows(ls)
	local nm = ls.token.name

	return nm == 'else' or nm == 'elseif' or nm == 'end' or nm == 'until' or nm == '<eos>'
end

local function luaX_is_sep(ls, pos)
	local eq = ls.src:match('^%[(=*)%[', pos)
	local value = false

	if eq then
		value = #eq
	end

	return value
end

local function luaX_str_line(ls, pos, line)
	local src = ls.src

	while true do
		local white = src:match('^[\r\n]', pos)

		if white == '\r' then
			if src:sub(pos + 1, pos + 1) == '\n' then
				pos = pos + 1
			end
		elseif white ~= '\n' then
			break
		end

		pos = pos + 1
		line = line + 1
	end

	return pos, line
end

local function luaX_skip_line(ls)
	ls.pos, ls.line = luaX_str_line(ls, ls.pos, ls.line)
end

local function luaX_skip_white(ls)
	local src = ls.src
	local pos = ls.pos
	local white

	repeat
		white = src:match('^%s', pos)
		pos = pos + 1

		if white == '\r' or white == '\n' then
			white = nil
		end
	until white == nil

	ls.pos = pos - 1
end

local function luaX_init_keyword(_, token)
	local slice = token.slice
	local name

	for i = #luaX_keywords, 1, -1 do
		local k = luaX_keywords[i]

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

local function luaX_init_symbol(ls, token)
	local src = ls.src
	local pos = ls.pos
	local name

	for i = #luaX_symbols, 1, -1 do
		local s = luaX_symbols[i]
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

local function luaX_init_name(ls, token)
	local _, e, name = ls.src:find('^([%w_]+)', ls.pos)

	token.name = '<name>'
	token.slice = name
	ls.pos = e + 1
end

local function luaX_init_numeric(ls, token)
	local _, e, num = ls.src:find('^([%x%.xX]*[eEpP]?[+-]?%x+)', ls.pos)
	local value = tonumber(num)
	local name

	if value == nil then
		luaX_syntax_error(ls, 'malformed number')
	end

	if math.tointeger(value) then
		name = '<integer>'
	else
		name = '<number>'
	end

	ls.pos = e + 1
	token.name = name
	token.slice = num
end

local function luaX_esc_hexadecimal(ls, pos)
	local _, e, num = ls.src:find('^(%x%x)', pos + 1)
	local esc

	if num then
		esc = string.char(tonumber(num))
	else
		luaX_syntax_error(ls, 'should be 2 hexadecimal digits')
	end

	return e, esc
end

local function luaX_esc_unicode(ls, pos)
	local _, e, num = ls.src:find('^{(%x+)}', pos + 1)
	local esc

	if num then
		num = tonumber(num, 16)

		if num < 0x11000 then
			esc = utf8.char(num)
		else
			luaX_syntax_error(ls, '`%X` should be between 0 and 10FFF', num)
		end
	else
		luaX_syntax_error(ls, 'should be hexadecimal digits')
	end

	return e, esc
end

local function luaX_esc_decimal(ls, pos)
	local _, e, num = ls.src:find('(%d+)', pos)
	local esc
	num = tonumber(num)

	if num < 256 then
		esc = string.char(num)
	else
		luaX_syntax_error(ls, '`%i` should be between 0 and 255', num)
	end

	return e, esc
end

local function luaX_esc_special(ls, pos)
	local esc = luaX_escapes[ls.src:sub(pos, pos)]

	if esc == nil then
		luaX_syntax_error(ls, 'invalid escape sequence')
	end

	return pos, esc
end

local function luaX_init_string(ls, token)
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
				pos, esc = luaX_esc_hexadecimal(ls, pos)
			elseif lsc == 'u' then
				pos, esc = luaX_esc_unicode(ls, pos)
			elseif tonumber(lsc) then
				pos, esc = luaX_esc_decimal(ls, pos)
			else
				pos, esc = luaX_esc_special(ls, pos)
			end

			table.insert(str, esc)
		elseif lsc == '\r' or lsc == '\n' then
			pos, line = luaX_str_line(ls, pos, line)
		elseif lsc == quo then
			pos = pos + 1
			break
		else
			table.insert(str, lsc)
		end
	end

	if lsc ~= quo then
		luaX_syntax_error(ls, 'unfinished string')
	end

	ls.pos = pos
	ls.line = line
	token.name = '<string>'
	token.slice = table.concat(str)
end

local function luaX_init_long_string(ls, token, sep)
	local src, len = ls.src, #ls.src
	local line = ls.line
	local stt = ls.pos + sep + 2
	local pos = stt
	local ok = false

	while pos <= len do
		local lsc = src:sub(pos, pos)

		if lsc == '\r' or lsc == '\n' then
			pos, line = luaX_str_line(ls, pos, line)
		elseif lsc == ']' then
			local init = pos + 1
			for _ = 1, sep + 1 do
				pos = pos + 1
				lsc = src:sub(pos, pos)
				if lsc ~= '=' then
					break
				end
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

	if not ok then
		luaX_syntax_error(ls, 'unfinished long string')
	end

	ls.pos = pos
	ls.line = line
	token.name = '<string>'
	token.slice = src:sub(stt, pos - sep - 3)
end

local function luaX_str_comment(ls)
	local src, len = ls.src, #ls.src
	local stt = ls.pos + 2
	local pos = stt

	while pos <= len do
		local lsc = src:sub(pos, pos)
		pos = pos + 1

		if lsc == '\r' or lsc == '\n' then
			break
		end
	end

	ls.pos = pos - 1
	return src:sub(stt, pos - 2)
end

function luaX_next(ls)
	local token = {}
	local src = ls.src
	local pos

	while true do
		pos = ls.pos
		if src:find('^[\r\n]', pos) then -- newline
			luaX_skip_line(ls)
		elseif src:find('^%s', pos) then -- whitespace
			luaX_skip_white(ls)
		elseif src:find('^%-%-', pos) then -- comments
			local sep = luaX_is_sep(ls, pos + 2)
			local cmt

			if sep then
				ls.pos = pos + 2
				luaX_init_long_string(ls, token, sep)

				token.name = nil
				cmt = token.slice
			else
				cmt = luaX_str_comment(ls)
			end

			table.insert(ls.cmts, cmt)
		else
			break
		end
	end

	if src:find('^[%a_]', pos) then
		luaX_init_name(ls, token)
		luaX_init_keyword(ls, token)
	elseif src:find('^%d', pos) then
		luaX_init_numeric(ls, token)
	elseif src:find('^%p', pos) and luaX_init_symbol(ls, token) then
		local name = token.name

		if name == '.' and src:find('^%d', pos + 1) then -- number
			ls.pos = ls.pos - 1
			luaX_init_numeric(ls, token)
		elseif name == '"' or name == '\'' then -- string
			ls.pos = ls.pos - 1
			luaX_init_string(ls, token)
		elseif name == '[' then -- long string
			local sep = luaX_is_sep(ls, ls.pos - 1)

			if sep then
				ls.pos = ls.pos - 1
				luaX_init_long_string(ls, token, sep)
			end
		end
	elseif pos > #src then
		token.name = '<eos>'
	else
		luaX_syntax_unexpected(ls)
	end

	ls.token = token
end

return {
	binary_p = luaX_binary_p,
	follows = luaX_follows,
	next = luaX_next,
	syntax_closes = luaX_syntax_closes,
	syntax_error = luaX_syntax_error,
	syntax_expect = luaX_syntax_expect,
	syntax_unexpected = luaX_syntax_unexpected,
	test_next = luaX_test_next,
	unary_p = luaX_unary_p,
	unary_pvalue = luaX_unary_pvalue,
}
