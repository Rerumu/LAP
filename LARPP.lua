-- source to AST parser module
local luaP_expression, luaP_stat_list
local luaO_LexState, luaO_Node
local luaX_binary_p, luaX_follows, luaX_next, luaX_syntax_closes, luaX_syntax_error,
						luaX_syntax_expect, luaX_test_next, luaX_unary_p, luaX_unary_pvalue

local luaP_lookup_stat = {}
local luaP_lookup_exp = {}

do
	local luaO = require('LARPO')
	local luaX = require('LARPL')

	luaO_LexState = luaO.LexState
	luaO_Node = luaO.Node

	luaX_binary_p = luaX.binary_p
	luaX_follows = luaX.follows
	luaX_next = luaX.next
	luaX_syntax_closes = luaX.syntax_closes
	luaX_syntax_error = luaX.syntax_error
	luaX_syntax_expect = luaX.syntax_expect
	luaX_test_next = luaX.test_next
	luaX_unary_p = luaX.unary_p
	luaX_unary_pvalue = luaX.unary_pvalue
end

local function aux_name_to_exp(n)
	n.nast = 'Literal'
	n.tt = 'String'
	n.value = n.name
	n.name = nil

	return n
end

local function luaP_exp_literal(ls, name, value)
	luaX_next(ls) -- `literal`
	return luaO_Node.Literal(ls, name, value)
end

local function luaP_name(ls)
	local name = luaO_Node.Name(ls, ls.token.slice)

	luaX_syntax_expect(ls, '<name>')
	return name
end

local function luaP_name_list(ls)
	local names = {}

	repeat
		local name = luaP_name(ls)

		table.insert(names, name)
	until not luaX_test_next(ls, ',')

	return names
end

local function luaP_name_str(ls) return aux_name_to_exp(luaP_name(ls)) end

local function luaP_param_list(ls)
	local line = ls.line
	local params = {}

	luaX_syntax_expect(ls, '(')
	while ls.token.name ~= ')' do
		local var = ls.token.name == '...' and luaP_exp_literal(ls, 'Vararg') or luaP_name(ls)

		table.insert(params, var)

		if not luaX_test_next(ls, ',') then break end
	end

	luaX_syntax_closes(ls, line, '(', ')')
	return params
end

local function luaP_func_name(ls)
	local expr = luaP_name(ls)
	local method

	while luaX_test_next(ls, '.') do
		local index = luaP_name_str(ls)
		expr = luaO_Node.Index(ls, expr, index)
	end

	method = luaX_test_next(ls, ':')
	if method then
		local index = luaP_name_str(ls)
		expr = luaO_Node.Index(ls, expr, index)
	end

	return expr, method
end

local function luaP_exp_list(ls)
	local explist = {}

	repeat
		local e = luaP_expression(ls)

		table.insert(explist, e)
	until not luaX_test_next(ls, ',')

	return explist
end

local function luaP_table_constructor(ls)
	local line = ls.line
	local list = {}
	local size_array = 0
	local size_hash = 0

	luaX_next(ls) -- `{`
	while ls.token.name ~= '}' do
		if ls.token.name == '[' then
			local kvp = {}
			local dline = ls.line

			luaX_next(ls) -- `[`
			kvp.key = luaP_expression(ls)

			luaX_syntax_closes(ls, dline, '[', ']')
			luaX_syntax_expect(ls, '=')
			kvp.value = luaP_expression(ls)

			size_hash = size_hash + 1
			table.insert(list, kvp)
		else
			local sub = luaP_expression(ls)
			local is_name = sub.nast == 'Suffixed' and #sub.suffixes == 0

			if is_name and ls.token.name == '=' then -- hash part
				local kvp = {}
				luaX_next(ls) -- `=`

				kvp.key = aux_name_to_exp(sub)
				kvp.value = luaP_expression(ls)

				size_hash = size_hash + 1
				table.insert(list, kvp)
			else -- array part
				size_array = size_array + 1
				table.insert(list, sub)
			end
		end

		if not (luaX_test_next(ls, ',') or luaX_test_next(ls, ';')) then break end
	end

	luaX_syntax_closes(ls, line, '{', '}')
	return luaO_Node.Table(ls, list, size_array, size_hash)
end

local function luaP_param_call(ls, name, index)
	local params

	if name == '(' then
		local line = ls.line

		luaX_next(ls)
		if ls.token.name ~= ')' then params = luaP_exp_list(ls) end

		luaX_syntax_closes(ls, line, '(', ')')
	elseif name == '{' then
		params = {luaP_table_constructor(ls)}
	elseif ls.token.name == '<string>' then
		params = {luaP_exp_literal(ls, 'String', ls.token.slice)}
	else
		luaX_syntax_expect(ls, '<params>')
	end

	if index then
		return luaO_Node.CallMethod(ls, index, params)
	else
		return luaO_Node.Call(ls, params)
	end
end

local function luaP_exp_prefix(ls)
	local name = ls.token.name
	local expr

	if name == '(' then
		local line = ls.line
		local value

		luaX_next(ls)
		value = luaP_expression(ls)
		expr = luaO_Node.Parens(ls, value)

		luaX_syntax_closes(ls, line, '(', ')')
	elseif name == '<name>' then
		expr = luaP_name(ls)
	else
		luaX_syntax_expect(ls, '<prefix>')
	end

	return expr
end

local function luaP_exp_suffixed(ls)
	local prefix = luaP_exp_prefix(ls)
	local suffixes = {}

	while true do
		local name = ls.token.name
		local suffix

		if name == '.' then
			local index

			luaX_next(ls)
			index = luaP_name_str(ls)
			suffix = luaO_Node.Index(ls, index)
		elseif name == ':' then
			local index

			luaX_next(ls)
			index = luaP_name_str(ls)
			suffix = luaP_param_call(ls, ls.token.name, index)
		elseif name == '[' then
			local line = ls.line
			local index

			luaX_next(ls)
			index = luaP_expression(ls)
			suffix = luaO_Node.Index(ls, index)

			luaX_syntax_closes(ls, line, '[', ']')
		elseif name == '(' or name == '{' or name == '<string>' then
			suffix = luaP_param_call(ls, name, nil)
		else
			break
		end

		table.insert(suffixes, suffix)
	end

	return luaO_Node.Suffixed(ls, prefix, suffixes)
end

luaP_lookup_exp['{'] = luaP_table_constructor

luaP_lookup_exp['function'] = function(ls)
	local line = ls.line
	local params, body

	luaX_next(ls) -- `function`
	params = luaP_param_list(ls)
	body = luaP_stat_list(ls)

	luaX_syntax_closes(ls, line, 'function', 'end')
	return luaO_Node.Function(ls, nil, params, body)
end

luaP_lookup_exp['true'] = function(ls) return luaP_exp_literal(ls, 'Boolean', true) end

luaP_lookup_exp['false'] = function(ls) return luaP_exp_literal(ls, 'Boolean', false) end

luaP_lookup_exp['nil'] = function(ls) return luaP_exp_literal(ls, 'Nil') end

luaP_lookup_exp['...'] = function(ls) return luaP_exp_literal(ls, 'Vararg') end

luaP_lookup_exp['<integer>'] = function(ls)
	return luaP_exp_literal(ls, 'Integer', tonumber(ls.token.slice))
end

luaP_lookup_exp['<number>'] = function(ls)
	return luaP_exp_literal(ls, 'Number', tonumber(ls.token.slice))
end

luaP_lookup_exp['<string>'] = function(ls) return luaP_exp_literal(ls, 'String', ls.token.slice) end

local luaP_sub_expr

local function luaP_exp_unary(ls)
	local un_op = ls.token.name

	luaX_next(ls)

	local rhs = luaP_sub_expr(ls, luaX_unary_pvalue)

	return luaO_Node.UnOp(ls, un_op, rhs)
end

local function luaP_exp_simple(ls)
	local func = luaP_lookup_exp[ls.token.name]

	if func then
		return func(ls)
	else
		return luaP_exp_suffixed(ls)
	end
end

function luaP_sub_expr(ls, min_prec)
	local lhs

	if luaX_unary_p[ls.token.name] then
		lhs = luaP_exp_unary(ls)
	else
		lhs = luaP_exp_simple(ls)
	end

	while luaX_binary_p[ls.token.name] do
		local name = ls.token.name
		local prec = luaX_binary_p[name]

		if prec.left < min_prec then break end

		luaX_next(ls)

		local rhs = luaP_sub_expr(ls, prec.right)

		lhs = luaO_Node.BinOp(ls, name, lhs, rhs)
	end

	return lhs
end

function luaP_expression(ls) return luaP_sub_expr(ls, 0) end

local function luaP_stat_locfunc(ls)
	local line = ls.line
	local name, params, body, func

	luaX_next(ls) -- `function`
	name = luaP_name(ls)
	params = luaP_param_list(ls)
	body = luaP_stat_list(ls)
	func = luaO_Node.Function(ls, name, params, body)

	luaX_syntax_closes(ls, line, 'function', 'end')
	return luaO_Node.LocalFunction(ls, name, func)
end

local function luaP_stat_locvar(ls)
	local names = luaP_name_list(ls)
	local values

	if luaX_test_next(ls, '=') then values = luaP_exp_list(ls) end

	return luaO_Node.LocalAssignment(ls, names, values)
end

local function luaP_stat_for_numeric(ls, var)
	local start, last, step

	luaX_next(ls) -- '='
	start = luaP_expression(ls)

	luaX_syntax_expect(ls, ',')
	last = luaP_expression(ls)

	if luaX_test_next(ls, ',') then step = luaP_expression(ls) end

	return luaO_Node.ForRange(ls, var, start, last, step)
end

local function luaP_stat_for_generic(ls, var)
	local vars, params

	if luaX_test_next(ls, ',') then
		vars = luaP_name_list(ls)
	else
		vars = {}
	end

	table.insert(vars, 1, var)
	luaX_syntax_expect(ls, 'in')

	params = luaP_exp_list(ls)
	return luaO_Node.ForIterator(ls, vars, params)
end

local function luaP_stat_if_sub(ls)
	local sub = {}

	luaX_next(ls) -- `if`/`elseif`
	sub.cond = luaP_expression(ls)

	luaX_syntax_expect(ls, 'then')
	sub.body = luaP_stat_list(ls)
	return sub
end

luaP_lookup_stat['break'] = function(ls)
	luaX_next(ls) -- `break`
	return luaO_Node.Break(ls)
end

luaP_lookup_stat['do'] = function(ls)
	local line = ls.line
	local body

	luaX_next(ls) -- `do`
	body = luaP_stat_list(ls)

	luaX_syntax_closes(ls, line, 'do', 'end')
	return luaO_Node.Do(ls, body)
end

luaP_lookup_stat['for'] = function(ls)
	local line = ls.line
	local stat, name, var

	luaX_next(ls) -- `for`
	var = luaP_name(ls)
	name = ls.token.name

	if name == '=' then
		stat = luaP_stat_for_numeric(ls, var)
	elseif name == 'in' or name == ',' then
		stat = luaP_stat_for_generic(ls, var)
	else
		luaX_syntax_expect(ls, '= || in || ,')
	end

	luaX_syntax_expect(ls, 'do')
	stat.body = luaP_stat_list(ls)

	luaX_syntax_closes(ls, line, 'for', 'end')
	return stat
end

luaP_lookup_stat['function'] = function(ls)
	local line = ls.line
	local name, method, params, body

	luaX_next(ls) -- `function`
	name, method = luaP_func_name(ls)
	params = luaP_param_list(ls)
	body = luaP_stat_list(ls)

	if method then table.insert(params, 1, luaO_Node.Name(ls, 'self')) end

	luaX_syntax_closes(ls, line, 'function', 'end')
	return luaO_Node.Function(ls, name, params, body)
end

luaP_lookup_stat['goto'] = function(ls)
	local label

	luaX_next(ls) -- `goto`
	label = luaP_name(ls)

	return luaO_Node.Goto(ls, label)
end

luaP_lookup_stat['if'] = function(ls)
	local line = ls.line
	local list = {}
	local base

	repeat
		local sub = luaP_stat_if_sub(ls)

		table.insert(list, sub)
	until ls.token.name ~= 'elseif'

	if luaX_test_next(ls, 'else') then base = luaP_stat_list(ls) end

	luaX_syntax_closes(ls, line, 'if', 'end')
	return luaO_Node.If(ls, list, base)
end

luaP_lookup_stat['local'] = function(ls)
	luaX_next(ls) -- `local`
	if ls.token.name == 'function' then
		return luaP_stat_locfunc(ls)
	else
		return luaP_stat_locvar(ls)
	end
end

luaP_lookup_stat['repeat'] = function(ls)
	local line = ls.line
	local body, cond

	luaX_next(ls) -- `repeat`
	body = luaP_stat_list(ls)

	luaX_syntax_closes(ls, line, 'repeat', 'until')
	cond = luaP_expression(ls)

	return luaO_Node.Repeat(ls, cond, body)
end

luaP_lookup_stat['return'] = function(ls)
	local values

	luaX_next(ls) -- `return`
	if not luaX_follows(ls) then values = luaP_exp_list(ls) end

	return luaO_Node.Return(ls, values)
end

luaP_lookup_stat['while'] = function(ls)
	local line = ls.line
	local cond, body

	luaX_next(ls) -- `while`
	cond = luaP_expression(ls)

	luaX_syntax_expect(ls, 'do')
	body = luaP_stat_list(ls)

	luaX_syntax_closes(ls, line, 'while', 'end')
	return luaO_Node.While(ls, cond, body)
end

luaP_lookup_stat['::'] = function(ls)
	local line = ls.line
	local label

	luaX_next(ls) -- `::`
	label = luaP_name(ls)

	luaX_syntax_closes(ls, line, '::', '::')
	return luaO_Node.Label(ls, label)
end

local function aux_is_named(expr)
	if expr.nast == 'Suffixed' then
		local last = expr.suffixes[#expr.suffixes]

		return not last or last.nast == 'Index'
	end

	return false
end

local function luaP_stat_exp(ls)
	local stat = luaP_expression(ls)

	if aux_is_named(stat) then
		local explist = {stat}
		local vallist

		while luaX_test_next(ls, ',') do
			local e = luaP_expression(ls)

			if aux_is_named(e) then
				table.insert(explist, e)
			else
				luaX_syntax_error(ls, 'malformed assignment')
			end
		end

		luaX_syntax_expect(ls, '=')
		vallist = luaP_exp_list(ls)
		stat = luaO_Node.Assignment(ls, explist, vallist)
	end

	return stat
end

local function luaP_statement(ls)
	local func = luaP_lookup_stat[ls.token.name]

	if func then
		return func(ls)
	else
		return luaP_stat_exp(ls)
	end
end

function luaP_stat_list(ls)
	local stats = {}

	while not luaX_follows(ls) do
		local s = luaP_statement(ls)

		table.insert(stats, s)
	end

	return stats
end

local function luaP_src2ast(src)
	local ls = luaO_LexState(src)
	local stats

	luaX_next(ls)
	stats = luaP_stat_list(ls)

	do
		local last = stats[#stats]

		if last and #ls.cmts ~= 0 then last.cmts = table.move(ls.cmts, 1, #ls.cmts, 1, last.cmts or {}) end
	end

	return stats
end

return {src2ast = luaP_src2ast}
