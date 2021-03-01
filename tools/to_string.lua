local visitor_map = {}

local function indent(st) st.indent = st.indent + 1 end

local function dedent(st) st.indent = st.indent - 1 end

local function write(st, value) table.insert(st.buffer, value) end

local function pad(st) write(st, st.tab:rep(st.indent)) end

local function visit_node(st, node) visitor_map[node.node_name](st, node) end

local function visit_cs_list(st, list)
	for i, v in ipairs(list) do
		if i ~= 1 then write(st, ', ') end

		visit_node(st, v)
	end
end

local function visit_stat_list(st, list)
	indent(st)

	for _, v in ipairs(list) do
		pad(st)
		visit_node(st, v)
		write(st, '\n')
	end

	dedent(st)
end

function visitor_map.BinOp(st, expr)
	visit_node(st, expr.lhs)
	write(st, ' ')
	write(st, expr.operator)
	write(st, ' ')
	visit_node(st, expr.rhs)
end

function visitor_map.Call(st, expr)
	write(st, '(')
	visit_cs_list(st, expr.params)
	write(st, ')')
end

function visitor_map.CallMethod(st, expr)
	write(st, ':')
	write(st, expr.name)
	write(st, '(')
	visit_cs_list(st, expr.params)
	write(st, ')')
end

function visitor_map.Index(st, expr)
	write(st, '[')
	visit_node(st, expr.index)
	write(st, ']')
end

function visitor_map.Value(st, expr)
	local value

	if expr.type == 'String' then
		value = string.format('%q', expr.value)
	else
		value = tostring(expr.value)
	end

	write(st, value)
end

function visitor_map.Vararg(st, _) write(st, '...') end

function visitor_map.Name(st, expr) write(st, expr.name) end

function visitor_map.Parens(st, expr)
	write(st, '(')
	visit_node(st, expr.value)
	write(st, ')')
end

function visitor_map.Table(st, expr)
	write(st, '{\n')
	indent(st)

	for i, v in ipairs(expr.list) do
		if i ~= 1 then write(st, ',\n') end

		pad(st)

		if v.node_name then -- normal index
			visit_node(st, v)
		else -- key value pair
			write(st, '[')
			visit_node(st, v.key)
			write(st, '] = ')
			visit_node(st, v.value)
		end
	end

	dedent(st)
	write(st, '\n')
	pad(st)
	write(st, '}')
end

function visitor_map.Suffixed(st, expr)
	visit_node(st, expr.prefix)

	for _, v in ipairs(expr.suffixes) do visit_node(st, v) end
end

function visitor_map.UnOp(st, expr)
	write(st, expr.operator)
	write(st, ' ')
	visit_node(st, expr.rhs)
end

function visitor_map.Assignment(st, stat)
	visit_cs_list(st, stat.lhs)
	write(st, ' = ')
	visit_cs_list(st, stat.rhs)
end

function visitor_map.Break(st, _) write(st, 'break') end

function visitor_map.Do(st, stat)
	write(st, 'do\n')
	visit_stat_list(st, stat.body)
	pad(st)
	write(st, 'end')
end

function visitor_map.ForIterator(st, stat)
	write(st, 'for ')
	visit_cs_list(st, stat.vars)
	write(st, ' in ')
	visit_cs_list(st, stat.params)
	write(st, ' do\n')
	visit_stat_list(st, stat.body)
	pad(st)
	write(st, 'end')
end

function visitor_map.ForRange(st, stat)
	write(st, 'for ')
	visit_node(st, stat.var)
	write(st, ' = ')
	visit_node(st, stat.start)
	write(st, ', ')
	visit_node(st, stat.last)

	if stat.step then
		write(st, ', ')
		visit_node(st, stat.step)
	end

	write(st, ' do\n')
	visit_stat_list(st, stat.body)
	pad(st)
	write(st, 'end')
end

function visitor_map.Function(st, stat)
	write(st, 'function')

	if stat.name then
		write(st, ' ')
		write(st, table.concat(stat.name, '.'))
	end

	write(st, '(')
	visit_cs_list(st, stat.params)
	write(st, ')\n')
	visit_stat_list(st, stat.body)
	pad(st)
	write(st, 'end')
end

function visitor_map.Goto(st, stat)
	write(st, 'goto ')
	write(st, stat.label)
end

function visitor_map.If(st, stat)
	for i, v in ipairs(stat.list) do
		if i == 1 then
			write(st, 'if ')
		else
			pad(st)
			write(st, 'elseif ')
		end

		visit_node(st, v.cond)
		write(st, ' then\n')
		visit_stat_list(st, v.body)
	end

	if stat.base then
		pad(st)
		write(st, 'else\n')
		visit_stat_list(st, stat.base)
	end

	pad(st)
	write(st, 'end')
end

function visitor_map.Label(st, stat)
	write(st, '::')
	write(st, stat.label)
	write(st, '::')
end

function visitor_map.LocalAssignment(st, stat)
	write(st, 'local ')
	visit_cs_list(st, stat.names)

	if stat.values then
		write(st, ' = ')
		visit_cs_list(st, stat.values)
	end
end

function visitor_map.LocalFunction(st, stat)
	write(st, 'local function ')
	visit_node(st, stat.name)
	write(st, '(')
	visit_cs_list(st, stat.params)
	write(st, ')\n')
	visit_stat_list(st, stat.body)
	pad(st)
	write(st, 'end')
end

function visitor_map.Repeat(st, stat)
	write(st, 'repeat\n')
	visit_stat_list(st, stat.body)
	pad(st)
	write(st, 'until ')
	visit_node(st, stat.cond)
end

function visitor_map.Return(st, stat)
	write(st, 'return')

	if stat.values then
		write(st, ' ')
		visit_cs_list(st, stat.values)
	end
end

function visitor_map.While(st, stat)
	write(st, 'while ')
	visit_node(st, stat.cond)
	write(st, ' do\n')
	visit_stat_list(st, stat.body)
	pad(st)
	write(st, 'end')
end

local function new_state() return {buffer = {}, indent = -1, tab = '\t'} end

local function ast_to_str(ast)
	local state = new_state()

	visit_stat_list(state, ast)

	return table.concat(state.buffer)
end

return ast_to_str
