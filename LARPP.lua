-- source to AST parser module
local parse_expression, parse_stat_list
local LexState, with_lex
local lex_binary_bind, lex_follows, lex_next, lex_syntax_closes, lex_syntax_error,
						lex_syntax_expect, lex_test_next, lex_unary_bind, lex_unary_bind_value

local lookup_stat_map = {}
local lookup_exp_map = {}

do
	local luaO = require('LARPO')
	local luaX = require('LARPL')

	LexState = luaO.LexState
	with_lex = luaO.with_lex_state

	lex_binary_bind = luaX.binary_bind
	lex_follows = luaX.follows
	lex_next = luaX.next
	lex_syntax_closes = luaX.syntax_closes
	lex_syntax_error = luaX.syntax_error
	lex_syntax_expect = luaX.syntax_expect
	lex_test_next = luaX.test_next
	lex_unary_bind = luaX.unary_bind
	lex_unary_bind_value = luaX.unary_bind_value
end

local function aux_exp_ident(ls)
	local ident = ls.token.slice

	lex_syntax_expect(ls, '<ident>')
	return ident
end

local function aux_name_to_exp(n)
	n.node_name = 'Literal'
	n.tt = 'String'
	n.value = n.name
	n.name = nil

	return n
end

local function parse_exp_literal(ls, name, value)
	lex_next(ls) -- `literal`
	return with_lex(ls, 'Literal', name, value)
end

local function parse_name(ls) return with_lex(ls, 'Name', aux_exp_ident(ls)) end

local function parse_name_list(ls)
	local names = {}

	repeat
		local name = parse_name(ls)

		table.insert(names, name)
	until not lex_test_next(ls, ',')

	return names
end

local function parse_param_list(ls)
	local line = ls.line
	local params = {}

	lex_syntax_expect(ls, '(')
	while ls.token.name ~= ')' do
		local var = ls.token.name == '...' and parse_exp_literal(ls, 'Vararg') or parse_name(ls)

		table.insert(params, var)

		if not lex_test_next(ls, ',') then break end
	end

	lex_syntax_closes(ls, line, '(', ')')
	return params
end

local function parse_func_name(ls)
	local list = {aux_exp_ident(ls)}
	local method

	while lex_test_next(ls, '.') do table.insert(list, aux_exp_ident(ls)) end

	method = lex_test_next(ls, ':')
	if method then table.insert(list, aux_exp_ident(ls)) end

	return list, method
end

local function parse_exp_list(ls)
	local explist = {}

	repeat
		local e = parse_expression(ls)

		table.insert(explist, e)
	until not lex_test_next(ls, ',')

	return explist
end

local function parse_table_constructor(ls)
	local line = ls.line
	local list = {}
	local size_array = 0
	local size_hash = 0

	lex_next(ls) -- `{`
	while ls.token.name ~= '}' do
		if ls.token.name == '[' then
			local kvp = {}
			local dline = ls.line

			lex_next(ls) -- `[`
			kvp.key = parse_expression(ls)

			lex_syntax_closes(ls, dline, '[', ']')
			lex_syntax_expect(ls, '=')
			kvp.value = parse_expression(ls)

			size_hash = size_hash + 1
			table.insert(list, kvp)
		else
			local sub = parse_expression(ls)
			local is_name = sub.node_name == 'Suffixed' and #sub.suffixes == 0

			if is_name and ls.token.name == '=' then -- hash part
				local kvp = {}
				lex_next(ls) -- `=`

				kvp.key = aux_name_to_exp(sub.prefix)
				kvp.value = parse_expression(ls)

				size_hash = size_hash + 1
				table.insert(list, kvp)
			else -- array part
				size_array = size_array + 1
				table.insert(list, sub)
			end
		end

		if not (lex_test_next(ls, ',') or lex_test_next(ls, ';')) then break end
	end

	lex_syntax_closes(ls, line, '{', '}')
	return with_lex(ls, 'Table', list, size_array, size_hash)
end

local function parse_param_call(ls, name, index)
	local params

	if name == '(' then
		local line = ls.line

		lex_next(ls)
		if ls.token.name ~= ')' then params = parse_exp_list(ls) end

		lex_syntax_closes(ls, line, '(', ')')
	elseif name == '{' then
		params = {parse_table_constructor(ls)}
	elseif ls.token.name == '<string>' then
		params = {parse_exp_literal(ls, 'String', ls.token.slice)}
	else
		lex_syntax_expect(ls, '<params>')
	end

	if index then
		return with_lex(ls, 'CallMethod', index, params)
	else
		return with_lex(ls, 'Call', params)
	end
end

local function parse_exp_prefix(ls)
	local name = ls.token.name
	local expr

	if name == '(' then
		local line = ls.line
		local value

		lex_next(ls)
		value = parse_expression(ls)
		expr = with_lex(ls, 'Parens', value)

		lex_syntax_closes(ls, line, '(', ')')
	elseif name == '<ident>' then
		expr = parse_name(ls)
	else
		lex_syntax_expect(ls, '<prefix>')
	end

	return expr
end

local function parse_exp_suffixed(ls)
	local prefix = parse_exp_prefix(ls)
	local suffixes = {}

	while true do
		local name = ls.token.name
		local suffix

		if name == '.' then
			local index

			lex_next(ls)
			index = aux_name_to_exp(parse_name(ls))
			suffix = with_lex(ls, 'Index', index)
		elseif name == ':' then
			local index

			lex_next(ls)
			index = aux_exp_ident(ls)
			suffix = parse_param_call(ls, ls.token.name, index)
		elseif name == '[' then
			local line = ls.line
			local index

			lex_next(ls)
			index = parse_expression(ls)
			suffix = with_lex(ls, 'Index', index)

			lex_syntax_closes(ls, line, '[', ']')
		elseif name == '(' or name == '{' or name == '<string>' then
			suffix = parse_param_call(ls, name, nil)
		else
			break
		end

		table.insert(suffixes, suffix)
	end

	return with_lex(ls, 'Suffixed', prefix, suffixes)
end

lookup_exp_map['{'] = parse_table_constructor

lookup_exp_map['function'] = function(ls)
	local line = ls.line
	local params, body

	lex_next(ls) -- `function`
	params = parse_param_list(ls)
	body = parse_stat_list(ls)

	lex_syntax_closes(ls, line, 'function', 'end')
	return with_lex(ls, 'Function', nil, params, body)
end

lookup_exp_map['true'] = function(ls) return parse_exp_literal(ls, 'Boolean', true) end

lookup_exp_map['false'] = function(ls) return parse_exp_literal(ls, 'Boolean', false) end

lookup_exp_map['nil'] = function(ls) return parse_exp_literal(ls, 'Nil') end

lookup_exp_map['...'] = function(ls) return parse_exp_literal(ls, 'Vararg') end

lookup_exp_map['<integer>'] = function(ls)
	return parse_exp_literal(ls, 'Integer', tonumber(ls.token.slice))
end

lookup_exp_map['<number>'] = function(ls)
	return parse_exp_literal(ls, 'Number', tonumber(ls.token.slice))
end

lookup_exp_map['<string>'] = function(ls) return parse_exp_literal(ls, 'String', ls.token.slice) end

local parse_sub_expr

local function parse_exp_unary(ls)
	local un_op = ls.token.name

	lex_next(ls)

	local rhs = parse_sub_expr(ls, lex_unary_bind_value)

	return with_lex(ls, 'UnOp', un_op, rhs)
end

local function parse_exp_simple(ls)
	local func = lookup_exp_map[ls.token.name]

	if func then
		return func(ls)
	else
		return parse_exp_suffixed(ls)
	end
end

function parse_sub_expr(ls, min_prec)
	local lhs

	if lex_unary_bind[ls.token.name] then
		lhs = parse_exp_unary(ls)
	else
		lhs = parse_exp_simple(ls)
	end

	while lex_binary_bind[ls.token.name] do
		local name = ls.token.name
		local prec = lex_binary_bind[name]

		if prec.left < min_prec then break end

		lex_next(ls)

		local rhs = parse_sub_expr(ls, prec.right)

		lhs = with_lex(ls, 'BinOp', name, lhs, rhs)
	end

	return lhs
end

function parse_expression(ls) return parse_sub_expr(ls, 0) end

local function parse_stat_locfunc(ls)
	local line = ls.line
	local name, params, body, func

	lex_next(ls) -- `function`
	name = parse_name(ls)
	params = parse_param_list(ls)
	body = parse_stat_list(ls)

	lex_syntax_closes(ls, line, 'function', 'end')
	return with_lex(ls, 'LocalFunction', name, params, body)
end

local function parse_stat_locvar(ls)
	local names = parse_name_list(ls)
	local values

	if lex_test_next(ls, '=') then values = parse_exp_list(ls) end

	return with_lex(ls, 'LocalAssignment', names, values)
end

local function parse_stat_for_numeric(ls, var)
	local start, last, step

	lex_next(ls) -- '='
	start = parse_expression(ls)

	lex_syntax_expect(ls, ',')
	last = parse_expression(ls)

	if lex_test_next(ls, ',') then step = parse_expression(ls) end

	return with_lex(ls, 'ForRange', var, start, last, step)
end

local function parse_stat_for_generic(ls, var)
	local vars, params

	if lex_test_next(ls, ',') then
		vars = parse_name_list(ls)
	else
		vars = {}
	end

	table.insert(vars, 1, var)
	lex_syntax_expect(ls, 'in')

	params = parse_exp_list(ls)
	return with_lex(ls, 'ForIterator', vars, params)
end

local function parse_stat_if_sub(ls)
	local sub = {}

	lex_next(ls) -- `if`/`elseif`
	sub.cond = parse_expression(ls)

	lex_syntax_expect(ls, 'then')
	sub.body = parse_stat_list(ls)
	return sub
end

lookup_stat_map['break'] = function(ls)
	lex_next(ls) -- `break`
	return with_lex(ls, 'Break')
end

lookup_stat_map['do'] = function(ls)
	local line = ls.line
	local body

	lex_next(ls) -- `do`
	body = parse_stat_list(ls)

	lex_syntax_closes(ls, line, 'do', 'end')
	return with_lex(ls, 'Do', body)
end

lookup_stat_map['for'] = function(ls)
	local line = ls.line
	local stat, name, var

	lex_next(ls) -- `for`
	var = parse_name(ls)
	name = ls.token.name

	if name == '=' then
		stat = parse_stat_for_numeric(ls, var)
	elseif name == 'in' or name == ',' then
		stat = parse_stat_for_generic(ls, var)
	else
		lex_syntax_expect(ls, '= || in || ,')
	end

	lex_syntax_expect(ls, 'do')
	stat.body = parse_stat_list(ls)

	lex_syntax_closes(ls, line, 'for', 'end')
	return stat
end

lookup_stat_map['function'] = function(ls)
	local line = ls.line
	local name, method, params, body

	lex_next(ls) -- `function`
	name, method = parse_func_name(ls)
	params = parse_param_list(ls)
	body = parse_stat_list(ls)

	if method then table.insert(params, 1, with_lex(ls, 'Name', 'self')) end

	lex_syntax_closes(ls, line, 'function', 'end')
	return with_lex(ls, 'Function', name, params, body)
end

lookup_stat_map['goto'] = function(ls)
	local label

	lex_next(ls) -- `goto`
	label = aux_exp_ident(ls)

	return with_lex(ls, 'Goto', label)
end

lookup_stat_map['if'] = function(ls)
	local line = ls.line
	local list = {}
	local base

	repeat
		local sub = parse_stat_if_sub(ls)

		table.insert(list, sub)
	until ls.token.name ~= 'elseif'

	if lex_test_next(ls, 'else') then base = parse_stat_list(ls) end

	lex_syntax_closes(ls, line, 'if', 'end')
	return with_lex(ls, 'If', list, base)
end

lookup_stat_map['local'] = function(ls)
	lex_next(ls) -- `local`
	if ls.token.name == 'function' then
		return parse_stat_locfunc(ls)
	else
		return parse_stat_locvar(ls)
	end
end

lookup_stat_map['repeat'] = function(ls)
	local line = ls.line
	local body, cond

	lex_next(ls) -- `repeat`
	body = parse_stat_list(ls)

	lex_syntax_closes(ls, line, 'repeat', 'until')
	cond = parse_expression(ls)

	return with_lex(ls, 'Repeat', cond, body)
end

lookup_stat_map['return'] = function(ls)
	local values

	lex_next(ls) -- `return`
	if not lex_follows(ls) then values = parse_exp_list(ls) end

	return with_lex(ls, 'Return', values)
end

lookup_stat_map['while'] = function(ls)
	local line = ls.line
	local cond, body

	lex_next(ls) -- `while`
	cond = parse_expression(ls)

	lex_syntax_expect(ls, 'do')
	body = parse_stat_list(ls)

	lex_syntax_closes(ls, line, 'while', 'end')
	return with_lex(ls, 'While', cond, body)
end

lookup_stat_map['::'] = function(ls)
	local line = ls.line
	local label

	lex_next(ls) -- `::`
	label = aux_exp_ident(ls)

	lex_syntax_closes(ls, line, '::', '::')
	return with_lex(ls, 'Label', label)
end

lookup_stat_map[';'] = lex_next

local function aux_is_named(expr)
	if expr.node_name == 'Suffixed' then
		local last = expr.suffixes[#expr.suffixes]

		return not last or last.node_name == 'Index'
	end

	return false
end

local function parse_stat_exp(ls)
	local stat = parse_expression(ls)

	if aux_is_named(stat) then
		local explist = {stat}
		local vallist

		while lex_test_next(ls, ',') do
			local e = parse_expression(ls)

			if aux_is_named(e) then
				table.insert(explist, e)
			else
				lex_syntax_error(ls, 'malformed assignment')
			end
		end

		lex_syntax_expect(ls, '=')
		vallist = parse_exp_list(ls)
		stat = with_lex(ls, 'Assignment', explist, vallist)
	end

	return stat
end

local function parse_statement(ls)
	local func = lookup_stat_map[ls.token.name]

	if func then
		return func(ls)
	else
		return parse_stat_exp(ls)
	end
end

function parse_stat_list(ls)
	local stats = {}

	while not lex_follows(ls) do
		local s = parse_statement(ls)

		table.insert(stats, s)
	end

	return stats
end

local function parse_src2ast(src)
	local ls = LexState(src)
	local stats

	lex_next(ls)
	stats = parse_stat_list(ls)

	do
		local last = stats[#stats]

		if last and #ls.comment ~= 0 then
			last.comment = table.move(ls.comment, 1, #ls.comment, 1, last.comment or {})
		end
	end

	return stats
end

return {src2ast = parse_src2ast}
