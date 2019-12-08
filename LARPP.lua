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

local function luaP_name_to_exp(n)
	n.nast = 'LiteralExpr'
	n.tt = 'String'
	n.value = n.name
	n.name = nil

	return n
end

local function luaP_exp_literal(ls, name, value)
	luaX_next(ls) -- `literal`
	return luaO_Node.LiteralExpr(ls, name, value)
end

local function luaP_name(ls)
	local name = luaO_Node.NameExpr(ls, ls.token.slice)

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

local function luaP_name_str(ls)
	return luaP_name_to_exp(luaP_name(ls))
end

local function luaP_param_list(ls)
	local line = ls.line
	local params = {}

	luaX_syntax_expect(ls, '(')
	while ls.token.name ~= ')' do
		local var = ls.token.name == '...' and luaP_exp_literal(ls, 'Vararg') or luaP_name(ls)
		table.insert(params, var)

		if not luaX_test_next(ls, ',') then
			break
		end
	end

	luaX_syntax_closes(ls, line, '(', ')')
	return params
end

local function luaP_func_name(ls)
	local expr = luaP_name(ls)
	local method

	while luaX_test_next(ls, '.') do
		local index = luaP_name_str(ls)
		expr = luaO_Node.IndexExpr(ls, expr, index)
	end

	method = luaX_test_next(ls, ':')
	if method then
		local index = luaP_name_str(ls)
		expr = luaO_Node.IndexExpr(ls, expr, index)
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

local function luaP_exp_unary(ls)
	local expr = {}
	local now = expr

	while luaX_unary_p[ls.token.name] do
		local unop = luaO_Node.UnopExpr(ls, ls.token.name)
		luaX_next(ls)

		now.rhs = unop
		now = unop
	end

	return expr.rhs, now
end

local function luaP_table_constructor(ls)
	local line = ls.line
	local array = {}
	local hash = {}

	luaX_next(ls) -- `{`
	while ls.token.name ~= '}' do
		if ls.token.name == '[' then
			local kvp = {}
			local dline = ls.line

			luaX_next(ls) -- `[`
			kvp.index = #array
			kvp.key = luaP_expression(ls)

			luaX_syntax_closes(ls, dline, '[', ']')
			luaX_syntax_expect(ls, '=')
			kvp.value = luaP_expression(ls)
			table.insert(hash, kvp)
		else
			local sub = luaP_expression(ls)

			if sub.nast == 'NameExpr' and ls.token.name == '=' then -- hash part
				local kvp = {}
				luaX_next(ls) -- `=`

				kvp.index = #array
				kvp.key = luaP_name_to_exp(sub)
				kvp.value = luaP_expression(ls)
				table.insert(hash, kvp)
			else -- array part
				table.insert(array, sub)
			end
		end

		if not (luaX_test_next(ls, ',') or luaX_test_next(ls, ';')) then
			break
		end
	end

	luaX_syntax_closes(ls, line, '{', '}')
	return luaO_Node.TableExpr(ls, array, hash)
end

local function luaP_param_call(ls, func, name, index)
	local params

	if name == '(' then
		local line = ls.line

		luaX_next(ls)
		if ls.token.name ~= ')' then
			params = luaP_exp_list(ls)
		end

		luaX_syntax_closes(ls, line, '(', ')')
	elseif name == '{' then
		params = {luaP_table_constructor(ls)}
	elseif ls.token.name == '<string>' then
		params = {luaP_exp_literal(ls, 'String', ls.token.slice)}
	else
		luaX_syntax_expect(ls, '<params>')
	end

	if index then
		return luaO_Node.CallMethodExpr(ls, func, index, params)
	else
		return luaO_Node.CallExpr(ls, func, params)
	end
end

local function luaP_exp_base(ls)
	local name = ls.token.name
	local expr

	if name == '(' then
		local line = ls.line
		local value

		luaX_next(ls)
		value = luaP_expression(ls)
		expr = luaO_Node.ParensExpr(ls, value)

		luaX_syntax_closes(ls, line, '(', ')')
	elseif name == '<name>' then
		expr = luaP_name(ls)
	else
		luaX_syntax_expect(ls, '<exp>')
	end

	return expr
end

local function luaP_exp_suffix(ls)
	local expr = luaP_exp_base(ls)

	while true do
		local name = ls.token.name

		if name == '.' then
			local index

			luaX_next(ls)
			index = luaP_name_str(ls)
			expr = luaO_Node.IndexExpr(ls, expr, index)
		elseif name == ':' then
			local index

			luaX_next(ls)
			index = luaP_name_str(ls)
			expr = luaP_param_call(ls, expr, ls.token.name, index)
		elseif name == '[' then
			local line = ls.line
			local index

			luaX_next(ls)
			index = luaP_expression(ls)
			expr = luaO_Node.IndexExpr(ls, expr, index)

			luaX_syntax_closes(ls, line, '[', ']')
		elseif name == '(' or name == '{' or name == '<string>' then
			expr = luaP_param_call(ls, expr, name, nil)
		else
			break
		end
	end

	return expr
end

luaP_lookup_exp['{'] = luaP_table_constructor

luaP_lookup_exp['function'] = function(ls)
	local line = ls.line
	local params, body

	luaX_next(ls) -- `function`
	params = luaP_param_list(ls)
	body = luaP_stat_list(ls)

	luaX_syntax_closes(ls, line, 'function', 'end')
	return luaO_Node.FuncStat(ls, nil, params, body)
end

luaP_lookup_exp['true'] = function(ls)
	return luaP_exp_literal(ls, 'Boolean', true)
end

luaP_lookup_exp['false'] = function(ls)
	return luaP_exp_literal(ls, 'Boolean', false)
end

luaP_lookup_exp['nil'] = function(ls)
	return luaP_exp_literal(ls, 'Nil')
end

luaP_lookup_exp['...'] = function(ls)
	return luaP_exp_literal(ls, 'Vararg')
end

luaP_lookup_exp['<integer>'] = function(ls)
	return luaP_exp_literal(ls, 'Integer', tonumber(ls.token.slice))
end

luaP_lookup_exp['<number>'] = function(ls)
	return luaP_exp_literal(ls, 'Number', tonumber(ls.token.slice))
end

luaP_lookup_exp['<string>'] = function(ls)
	return luaP_exp_literal(ls, 'String', ls.token.slice)
end

local function luaP_exp_simple(ls)
	local uroot, ulast = luaP_exp_unary(ls)
	local func = luaP_lookup_exp[ls.token.name]
	local expr

	if func then
		expr = func(ls)
	else
		expr = luaP_exp_suffix(ls)
	end

	if uroot then
		ulast.rhs = expr
		expr = uroot
	end

	return expr
end

function luaP_expression(ls)
	local expr = luaP_exp_simple(ls)

	while luaX_binary_p[ls.token.name] do
		local op = luaO_Node.BinopExpr(ls, ls.token.name)
		local lopp = luaX_binary_p[op.operator].left
		local steals = luaX_unary_pvalue < lopp
		local value = expr
		local last

		while true do
			local nast = value.nast

			if (nast == 'UnopExpr' and steals) or
							(nast == 'BinopExpr' and luaX_binary_p[value.operator].right < lopp) then
				last = value
				value = last.rhs
			else
				break
			end
		end

		luaX_next(ls)
		op.rhs = luaP_exp_simple(ls)
		op.lhs = value

		if last then
			last.rhs = op
		else
			expr = op
		end
	end

	return expr
end

local function luaP_stat_locfunc(ls)
	local line = ls.line
	local name, params, body, func

	luaX_next(ls) -- `function`
	name = luaP_name(ls)
	params = luaP_param_list(ls)
	body = luaP_stat_list(ls)
	func = luaO_Node.FuncStat(ls, name, params, body)

	luaX_syntax_closes(ls, line, 'function', 'end')
	return luaO_Node.LocalFuncStat(ls, name, func)
end

local function luaP_stat_locvar(ls)
	local names = luaP_name_list(ls)
	local values

	if luaX_test_next(ls, '=') then
		values = luaP_exp_list(ls)
	end

	return luaO_Node.LocalStat(ls, names, values)
end

local function luaP_stat_for_numeric(ls, var)
	local limit, step

	luaX_next(ls) -- '='
	var = {name = var, value = luaP_expression(ls)}

	luaX_syntax_expect(ls, ',')
	limit = luaP_expression(ls)

	if luaX_test_next(ls, ',') then
		step = luaP_expression(ls)
	end

	return luaO_Node.ForRangeStat(ls, var, limit, step)
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
	return luaO_Node.ForIteratorStat(ls, vars, params)
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
	return luaO_Node.BreakStat(ls)
end

luaP_lookup_stat['do'] = function(ls)
	local line = ls.line
	local body

	luaX_next(ls) -- `do`
	body = luaP_stat_list(ls)

	luaX_syntax_closes(ls, line, 'do', 'end')
	return luaO_Node.DoStat(ls, body)
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

	if method then
		table.insert(params, luaO_Node.NameExpr(ls, 'self'))
	end

	luaX_syntax_closes(ls, line, 'function', 'end')
	return luaO_Node.FuncStat(ls, name, params, body)
end

luaP_lookup_stat['goto'] = function(ls)
	local label

	luaX_next(ls) -- `goto`
	label = luaP_name(ls)

	return luaO_Node.GotoStat(ls, label)
end

luaP_lookup_stat['if'] = function(ls)
	local line = ls.line
	local list = {}
	local base

	repeat
		local sub = luaP_stat_if_sub(ls)

		table.insert(list, sub)
	until ls.token.name ~= 'elseif'

	if luaX_test_next(ls, 'else') then
		base = luaP_stat_list(ls)
	end

	luaX_syntax_closes(ls, line, 'if', 'end')
	return luaO_Node.IfStat(ls, list, base)
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

	return luaO_Node.RepeatStat(ls, cond, body)
end

luaP_lookup_stat['return'] = function(ls)
	local values

	luaX_next(ls) -- `return`
	if not luaX_follows(ls) then
		values = luaP_exp_list(ls)
	end

	return luaO_Node.ReturnStat(ls, values)
end

luaP_lookup_stat['while'] = function(ls)
	local line = ls.line
	local cond, body

	luaX_next(ls) -- `while`
	cond = luaP_expression(ls)

	luaX_syntax_expect(ls, 'do')
	body = luaP_stat_list(ls)

	luaX_syntax_closes(ls, line, 'while', 'end')
	return luaO_Node.WhileStat(ls, cond, body)
end

luaP_lookup_stat['::'] = function(ls)
	local line = ls.line
	local label

	luaX_next(ls) -- `::`
	label = luaP_name(ls)

	luaX_syntax_closes(ls, line, '::', '::')
	return luaO_Node.LabelStat(ls, label)
end

local function luaP_stat_exp(ls)
	local stat = luaP_expression(ls)

	if stat.nast == 'NameExpr' or stat.nast == 'IndexExpr' then
		local explist = {stat}
		local vallist

		while luaX_test_next(ls, ',') do
			local e = luaP_expression(ls)

			if e.nast == 'NameExpr' or e.nast == 'IndexExpr' then
				table.insert(explist, e)
			else
				luaX_syntax_error(ls, 'malformed assignment')
			end
		end

		luaX_syntax_expect(ls, '=')
		vallist = luaP_exp_list(ls)
		stat = luaO_Node.AssignStat(ls, explist, vallist)
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

		if last and #ls.cmts ~= 0 then
			last.cmts = table.move(ls.cmts, 1, #ls.cmts, 1, last.cmts or {})
		end
	end

	return stats
end

return {src2ast = luaP_src2ast}
