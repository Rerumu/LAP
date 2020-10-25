local str_rule_map = {}
local str_value

local function indent(st) st.indent = st.indent + 1 end

local function dedent(st) st.indent = st.indent - 1 end

local function write(st, value) table.insert(st.buffer, value) end

local function pad(st) write(st, st.tab:rep(st.indent)) end

local function aux_str_cs_list(st, list)
	for i, v in ipairs(list) do
		if i ~= 1 then write(st, ', ') end

		str_value(st, v)
	end
end

local function aux_str_stat_list(st, list)
	indent(st)

	for _, v in ipairs(list) do
		pad(st)
		str_value(st, v)
		write(st, '\n')
	end

	dedent(st)
end

function str_rule_map.BinOp(st, expr)
	str_value(st, expr.lhs)
	write(st, ' ')
	write(st, expr.operator)
	write(st, ' ')
	str_value(st, expr.rhs)
end

function str_rule_map.Call(st, expr)
	write(st, '(')

	if expr.params then aux_str_cs_list(st, expr.params) end

	write(st, ')')
end

function str_rule_map.CallMethod(st, expr)
	write(st, ':')
	write(st, expr.name)
	write(st, '(')

	if expr.params then aux_str_cs_list(st, expr.params) end

	write(st, ')')
end

function str_rule_map.Index(st, expr)
	write(st, '[')
	str_value(st, expr.index)
	write(st, ']')
end

function str_rule_map.Value(st, expr)
	local value

	if expr.tt == 'Vararg' then
		value = '...'
	elseif expr.tt == 'String' then
		value = string.format('%q', expr.value)
	else
		value = tostring(expr.value)
	end

	write(st, value)
end

function str_rule_map.Name(st, expr) write(st, expr.name) end

function str_rule_map.Parens(st, expr)
	write(st, '(')
	str_value(st, expr.value)
	write(st, ')')
end

function str_rule_map.Table(st, expr)
	write(st, '{\n')
	indent(st)

	for i, v in ipairs(expr.list) do
		if i ~= 1 then write(st, ',\n') end

		pad(st)

		if v.node_name then -- normal index
			str_value(st, v)
		else -- key value pair
			write(st, '[')
			str_value(st, v.key)
			write(st, '] = ')
			str_value(st, v.value)
		end
	end

	dedent(st)
	write(st, '\n')
	pad(st)
	write(st, '}')
end

function str_rule_map.Suffixed(st, expr)
	str_value(st, expr.prefix)

	for _, v in ipairs(expr.suffixes) do str_value(st, v) end
end

function str_rule_map.UnOp(st, expr)
	write(st, expr.operator)
	write(st, ' ')
	str_value(st, expr.rhs)
end

function str_rule_map.Assignment(st, stat)
	aux_str_cs_list(st, stat.lhs)
	write(st, ' = ')
	aux_str_cs_list(st, stat.rhs)
end

function str_rule_map.Break(st, _) write(st, 'break') end

function str_rule_map.Do(st, stat)
	write(st, 'do\n')
	aux_str_stat_list(st, stat.body)
	pad(st)
	write(st, 'end')
end

function str_rule_map.ForIterator(st, stat)
	write(st, 'for ')
	aux_str_cs_list(st, stat.vars)
	write(st, ' in ')
	aux_str_cs_list(st, stat.params)
	write(st, ' do\n')
	aux_str_stat_list(st, stat.body)
	pad(st)
	write(st, 'end')
end

function str_rule_map.ForRange(st, stat)
	write(st, 'for ')
	str_value(st, stat.var)
	write(st, ' = ')
	str_value(st, stat.start)
	write(st, ', ')
	str_value(st, stat.last)

	if stat.step then
		write(st, ', ')
		str_value(st, stat.step)
	end

	write(st, ' do\n')
	aux_str_stat_list(st, stat.body)
	pad(st)
	write(st, 'end')
end

function str_rule_map.Function(st, stat)
	write(st, 'function')

	if stat.name then
		write(st, ' ')
		write(st, table.concat(stat.name, '.'))
	end

	write(st, '(')
	aux_str_cs_list(st, stat.params)
	write(st, ')\n')
	aux_str_stat_list(st, stat.body)
	pad(st)
	write(st, 'end')
end

function str_rule_map.Goto(st, stat)
	write(st, 'goto ')
	write(st, stat.label)
end

function str_rule_map.If(st, stat)
	for i, v in ipairs(stat.list) do
		if i == 1 then
			write(st, 'if ')
		else
			pad(st)
			write(st, 'elseif ')
		end

		str_value(st, v.cond)
		write(st, ' then\n')
		aux_str_stat_list(st, v.body)
	end

	if stat.base then
		pad(st)
		write(st, 'else\n')
		aux_str_stat_list(st, stat.base)
	end

	pad(st)
	write(st, 'end')
end

function str_rule_map.Label(st, stat)
	write(st, '::')
	write(st, stat.label)
	write(st, '::')
end

function str_rule_map.LocalAssignment(st, stat)
	write(st, 'local ')
	aux_str_cs_list(st, stat.names)

	if stat.values then
		write(st, ' = ')
		aux_str_cs_list(st, stat.values)
	end
end

function str_rule_map.LocalFunction(st, stat)
	write(st, 'local function ')
	str_value(st, stat.name)
	write(st, '(')
	aux_str_cs_list(st, stat.params)
	write(st, ')\n')
	aux_str_stat_list(st, stat.body)
	pad(st)
	write(st, 'end')
end

function str_rule_map.Repeat(st, stat)
	write(st, 'repeat\n')
	aux_str_stat_list(st, stat.body)
	pad(st)
	write(st, 'until ')
	str_value(st, stat.cond)
end

function str_rule_map.Return(st, stat)
	write(st, 'return')

	if stat.values then
		write(st, ' ')
		aux_str_cs_list(st, stat.values)
	end
end

function str_rule_map.While(st, stat)
	write(st, 'while ')
	str_value(st, stat.cond)
	write(st, ' do\n')
	aux_str_stat_list(st, stat.body)
	pad(st)
	write(st, 'end')
end

function str_value(st, value) str_rule_map[value.node_name](st, value) end

local function new_state() return {buffer = {}, indent = -1, tab = '\t'} end

local function ast_to_str(ast)
	local state = new_state()

	aux_str_stat_list(state, ast)

	return table.concat(state.buffer)
end

return ast_to_str
