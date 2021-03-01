local with_name = require('node').with_name
local visitor_fold_map = {}
local bin_op_num_map = {}
local bin_op_cmp_map = {}
local bin_op_map = {}
local un_op_map = {}

local function NO_OP(_, node) return node end

local function is_numeric(tt) return tt == 'Number' or tt == 'Integer' end

local function as_boolean(value)
	if value.node_name ~= 'Value' then return nil end

	local tt = value.type

	if is_numeric(tt) or tt == 'String' or tt == 'Table' then
		return true
	elseif tt == 'Nil' then
		return false
	elseif tt == 'Boolean' then
		return value.value
	end

	return nil
end

local function visit_node(st, node) return visitor_fold_map[node.node_name](st, node) end

local function visit_list(st, param)
	local list = {}

	for i, v in ipairs(param) do list[i] = visit_node(st, v) end

	return list
end

local function visit_expr_list(st, param)
	local len = #param
	local list = {}

	for i, v in ipairs(param) do
		local ret = {visit_node(st, v)}

		if i == len then
			for j, w in ipairs(ret) do list[i + j - 1] = w end
		else
			list[i] = ret[1] or with_name('Value', 'Nil')
		end
	end

	return list
end

local function has_side_effect(expr)
	local nn = expr.node_name

	if nn == 'Table' then
		for _, v in ipairs(expr.list) do
			if v.node_name then
				if has_side_effect(v) then return true end
			elseif has_side_effect(v.key) or has_side_effect(v.value) then
				return true
			end
		end

		return false
	else
		return nn ~= 'Value'
	end
end

un_op_map['-'] = function(rhs)
	if not is_numeric(rhs) then return nil end

	return with_name('Value', 'Number', -rhs.value)
end

un_op_map['#'] = function(rhs)
	local len

	if rhs.node_name == 'Table' and not has_side_effect(rhs) then
		len = rhs.size_array
	elseif rhs.type == 'String' then
		len = #rhs.value
	end

	if len then
		return with_name('Value', 'Number', len)
	else
		return nil
	end
end

un_op_map['not'] = function(rhs)
	local value

	if rhs.node_name == 'Table' then
		value = has_side_effect(rhs)
	else
		value = rhs.value
	end

	return with_name('Value', 'Boolean', not value)
end

bin_op_num_map['+'] = function(lhs, rhs) return lhs + rhs end
bin_op_num_map['-'] = function(lhs, rhs) return lhs - rhs end
bin_op_num_map['*'] = function(lhs, rhs) return lhs * rhs end
bin_op_num_map['/'] = function(lhs, rhs) return lhs / rhs end
bin_op_num_map['%'] = function(lhs, rhs) return lhs % rhs end
bin_op_num_map['^'] = function(lhs, rhs) return lhs ^ rhs end

bin_op_cmp_map['<'] = function(lhs, rhs) return lhs < rhs end
bin_op_cmp_map['<='] = function(lhs, rhs) return lhs <= rhs end
bin_op_cmp_map['=='] = function(lhs, rhs) return lhs == rhs end
bin_op_cmp_map['>'] = function(lhs, rhs) return lhs > rhs end
bin_op_cmp_map['>='] = function(lhs, rhs) return lhs >= rhs end
bin_op_cmp_map['~='] = function(lhs, rhs) return lhs ~= rhs end

bin_op_map['and'] = function(lhs, rhs)
	if lhs.value then
		return rhs
	else
		return lhs
	end
end

bin_op_map['or'] = function(lhs, rhs)
	if lhs.value then
		return lhs
	else
		return rhs
	end
end

local function is_comparison(lhs, rhs)
	local lhs_tt, rhs_tt = lhs.type, rhs.type

	if lhs_tt == rhs_tt then
		return is_numeric(lhs_tt) or lhs_tt == 'String'
	else
		return is_numeric(lhs_tt) and is_numeric(rhs_tt)
	end
end

local BIN_OP_COND = {
	{
		'Number',
		bin_op_num_map,
		function(lhs, rhs) return is_numeric(lhs.type) and is_numeric(rhs.type) end,
	},
	{'Boolean', bin_op_cmp_map, is_comparison},
}

visitor_fold_map.Name = NO_OP
visitor_fold_map.Value = NO_OP
visitor_fold_map.Vararg = NO_OP
visitor_fold_map.Break = NO_OP
visitor_fold_map.Goto = NO_OP
visitor_fold_map.Label = NO_OP

function visitor_fold_map.BinOp(st, expr)
	local lhs = visit_node(st, expr.lhs)
	local rhs = visit_node(st, expr.rhs)

	if lhs.node_name == 'Value' and rhs.node_name == 'Value' then
		local op = expr.operator

		for _, v in ipairs(BIN_OP_COND) do
			local func = v[2][op]

			if func and v[3](lhs, rhs) then
				local w = func(lhs.value, rhs.value)

				return with_name('Value', v[1], w)
			end
		end

		if bin_op_map[op] then return bin_op_map[op](lhs, rhs) end
	end

	return expr
end

function visitor_fold_map.Call(st, expr)
	local param_list = visit_expr_list(st, expr.params)

	return with_name('Call', param_list)
end

function visitor_fold_map.CallMethod(st, expr)
	local param_list = visit_expr_list(st, expr.params)

	return with_name('CallMethod', expr.name, param_list)
end

function visitor_fold_map.Index(st, expr)
	local index = visit_node(st, expr.index)

	return with_name('Index', index)
end

function visitor_fold_map.Parens(st, expr)
	local inner = visit_node(st, expr.value)

	if inner.node_name == 'Value' then
		return inner
	else
		return with_name('Parens', inner)
	end
end

function visitor_fold_map.Suffixed(st, expr)
	local prefix = visit_node(st, expr.prefix)
	local suffix_list = visit_list(st, expr.suffixes)

	return with_name('Suffixed', prefix, suffix_list)
end

function visitor_fold_map.Table(st, expr)
	local list = {}

	for i, v in ipairs(expr.list) do
		if v.node_name then
			list[i] = visit_node(st, v)
		else
			list[i] = {key = visit_node(st, v.key), value = visit_node(st, v.value)}
		end
	end

	return with_name('Table', list, expr.size_array, expr.size_hash)
end

function visitor_fold_map.UnOp(st, expr)
	local rhs = visit_node(st, expr.rhs)
	local nn = rhs.node_name

	if nn == 'Value' or nn == 'Table' then expr = un_op_map[expr.operator](rhs) or expr end

	return expr
end

function visitor_fold_map.Assignment(st, stat)
	local lhs_list = visit_list(st, stat.lhs)
	local rhs_list = visit_expr_list(st, stat.rhs)

	return with_name('Assignment', lhs_list, rhs_list)
end

function visitor_fold_map.Do(st, stat)
	local list = visit_list(st, stat.body)

	return with_name('Do', list)
end

function visitor_fold_map.ForIterator(st, stat)
	local param_list = visit_expr_list(st, stat.params)
	local body = visit_list(st, stat.body)

	return with_name('ForIterator', stat.vars, param_list, body)
end

function visitor_fold_map.ForRange(st, stat)
	local start = visit_node(st, stat.start)
	local last = visit_node(st, stat.last)
	local step = stat.step and visit_node(st, stat.step)
	local body = visit_list(st, stat.body)

	return with_name('ForRange', stat.var, start, last, step, body)
end

function visitor_fold_map.Function(st, stat)
	local body = visit_list(st, stat.body)

	return with_name('Function', stat.name, stat.params, body)
end

function visitor_fold_map.If(st, stat)
	local list = {}
	local base = stat.base

	for i, v in ipairs(stat.list) do
		local sub = {cond = visit_node(st, v.cond), body = visit_list(st, v.body)}
		local val = as_boolean(sub.cond)

		if val == true then
			return with_name('Do', sub.body)
		elseif val == nil then
			list[i] = sub
		end
	end

	if base then base = visit_list(st, base) end

	if #list == 0 then
		return with_name('Do', base)
	else
		return with_name('If', list, base)
	end
end

visitor_fold_map.LocalFunction = visitor_fold_map.Function

function visitor_fold_map.LocalAssignment(st, stat)
	local value_list = stat.values

	if value_list then value_list = visit_expr_list(st, value_list) end

	return with_name('LocalAssignment', stat.names, value_list)
end

function visitor_fold_map.Repeat(st, stat)
	local body = visit_list(st, stat.body)
	local cond = visit_node(st, stat.cond)

	if as_boolean(cond) == true then
		return with_name('Do', body)
	else
		return with_name('Repeat', cond, body)
	end
end

function visitor_fold_map.Return(st, stat)
	local value_list = stat.values and visit_expr_list(st, stat.values)

	return with_name('Return', value_list)
end

function visitor_fold_map.While(st, stat)
	local cond = visit_node(st, stat.cond)
	local body = visit_list(st, stat.body)

	if as_boolean(cond) == false then
		return with_name('Do', {})
	else
		return with_name('While', cond, body)
	end
end

local function fold_ast_const(ast)
	-- (currently) unused state
	local state = nil

	return visit_list(state, ast)
end

return fold_ast_const
