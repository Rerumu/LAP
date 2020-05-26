-- simple object constructors for nodes and states module
local luaO_Node = {}
local luaO_Node = {}

function luaO_Node.BinOp(op, lhs, rhs) return {operator = op, lhs = lhs, rhs = rhs} end

function luaO_Node.CallMethod(name, params) return {name = name, params = params} end

function luaO_Node.Call(params) return {params = params} end

function luaO_Node.Index(index) return {index = index} end

function luaO_Node.Literal(tt, value) return {tt = tt, value = value} end

function luaO_Node.Name(name) return {name = name} end

function luaO_Node.Parens(value) return {value = value} end

function luaO_Node.Table(list, size_array, size_hash)
	return {list = list, size_array = size_array, size_hash = size_hash}
end

function luaO_Node.Suffixed(prefix, suffixes) return {prefix = prefix, suffixes = suffixes} end

function luaO_Node.UnOp(op, rhs) return {operator = op, rhs = rhs} end

function luaO_Node.Assignment(lhs, rhs) return {lhs = lhs, rhs = rhs} end

function luaO_Node.Break() return {} end -- nothing lol

function luaO_Node.Do(body) return {body = body} end

function luaO_Node.ForIterator(vars, params) return {vars = vars, params = params, body = nil} end

function luaO_Node.ForRange(var, start, last, step)
	return {var = var, start = start, last = last, step = step, body = nil}
end

function luaO_Node.Function(name, params, body) return {name = name, params = params, body = body} end

function luaO_Node.Goto(label) return {label = label} end

function luaO_Node.If(list, base) return {list = list, base = base} end

function luaO_Node.Label(label) return {label = label} end

function luaO_Node.LocalFunction(name, params, body)
	return {name = name, params = params, body = body}
end

function luaO_Node.LocalAssignment(names, values) return {names = names, values = values} end

function luaO_Node.Repeat(cond, body) return {cond = cond, body = body} end

function luaO_Node.Return(values) return {values = values} end

function luaO_Node.While(cond, body) return {cond = cond, body = body} end

local function with_name(name, ...)
	local obj = luaO_Node[name](...)

	obj.node_name = name

	return obj
end

local function with_lex_state(ls, name, ...)
	local obj = luaO_Node[name](...)

	obj.node_name = name
	obj.node_line = ls.line
	obj.node_pos = ls.pos

	if #ls.comment ~= 0 then
		obj.comment = ls.comment
		ls.comment = {}
	end

	return obj
end

local function luaO_LexState(src) return {comment = {}, line = 1, pos = 1, src = src} end

return {LexState = luaO_LexState, with_name = with_name, with_lex_state = with_lex_state}
