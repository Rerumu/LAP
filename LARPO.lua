-- simple object constructors for nodes and states module
local Node = {}

function Node.BinOp(op, lhs, rhs) return {operator = op, lhs = lhs, rhs = rhs} end

function Node.CallMethod(name, params) return {name = name, params = params} end

function Node.Call(params) return {params = params} end

function Node.Index(index) return {index = index} end

function Node.Literal(tt, value) return {tt = tt, value = value} end

function Node.Name(name) return {name = name} end

function Node.Parens(value) return {value = value} end

function Node.Table(list, size_array, size_hash)
	return {list = list, size_array = size_array, size_hash = size_hash}
end

function Node.Suffixed(prefix, suffixes) return {prefix = prefix, suffixes = suffixes} end

function Node.UnOp(op, rhs) return {operator = op, rhs = rhs} end

function Node.Assignment(lhs, rhs) return {lhs = lhs, rhs = rhs} end

function Node.Break() return {} end -- nothing lol

function Node.Do(body) return {body = body} end

function Node.ForIterator(vars, params) return {vars = vars, params = params, body = nil} end

function Node.ForRange(var, start, last, step)
	return {var = var, start = start, last = last, step = step, body = nil}
end

function Node.Function(name, params, body) return {name = name, params = params, body = body} end

function Node.Goto(label) return {label = label} end

function Node.If(list, base) return {list = list, base = base} end

function Node.Label(label) return {label = label} end

function Node.LocalFunction(name, params, body) return {name = name, params = params, body = body} end

function Node.LocalAssignment(names, values) return {names = names, values = values} end

function Node.Repeat(cond, body) return {cond = cond, body = body} end

function Node.Return(values) return {values = values} end

function Node.While(cond, body) return {cond = cond, body = body} end

local function with_name(name, ...)
	local obj = Node[name](...)

	obj.node_name = name

	return obj
end

local function with_lex_state(ls, name, ...)
	local obj = Node[name](...)

	obj.node_name = name
	obj.node_line = ls.line
	obj.node_pos = ls.pos

	if #ls.comment ~= 0 then
		obj.comment = ls.comment
		ls.comment = {}
	end

	return obj
end

local function LexState(src) return {comment = {}, line = 1, pos = 1, src = src} end

return {LexState = LexState, with_name = with_name, with_lex_state = with_lex_state}
