-- simple object constructors for nodes and states module
local luaO_Node = {}
local luaO_preNode = {}

function luaO_preNode.BinOp(op, lhs, rhs) return {operator = op, lhs = lhs, rhs = rhs} end

function luaO_preNode.CallMethod(name, params) return {name = name, params = params} end

function luaO_preNode.Call(params) return {params = params} end

function luaO_preNode.Index(index) return {index = index} end

function luaO_preNode.Literal(tt, value) return {tt = tt, value = value} end

function luaO_preNode.Name(name) return {name = name} end

function luaO_preNode.Parens(value) return {value = value} end

function luaO_preNode.Table(list, size_array, size_hash)
	return {list = list, size_array = size_array, size_hash = size_hash}
end

function luaO_preNode.Suffixed(prefix, suffixes) return {prefix = prefix, suffixes = suffixes} end

function luaO_preNode.UnOp(op, rhs) return {operator = op, rhs = rhs} end

function luaO_preNode.Assignment(lhs, rhs) return {lhs = lhs, rhs = rhs} end

function luaO_preNode.Break() return {} end -- nothing lol

function luaO_preNode.Do(body) return {body = body} end

function luaO_preNode.ForIterator(vars, params) return {vars = vars, params = params, body = nil} end

function luaO_preNode.ForRange(var, limit, step)
	return {var = var, limit = limit, step = step, body = nil}
end

function luaO_preNode.Function(name, params, body) return
	{name = name, params = params, body = body} end

function luaO_preNode.Goto(label) return {label = label} end

function luaO_preNode.If(list, base) return {list = list, base = base} end

function luaO_preNode.LocalFunction(name, func) return {name = name, func = func} end

function luaO_preNode.LocalAssignment(names, values) return {names = names, values = values} end

function luaO_preNode.Repeat(cond, body) return {cond = cond, body = body} end

function luaO_preNode.Return(values) return {values = values} end

function luaO_preNode.While(cond, body) return {cond = cond, body = body} end

function luaO_preNode.Label(label) return {label = label} end

for name, func in pairs(luaO_preNode) do -- wraps funcs to hold debug info
	luaO_Node[name] = function(ls, ...)
		local obj = func(...)

		obj.nast = name

		if #ls.cmts ~= 0 then
			obj.cmts = ls.cmts
			ls.cmts = {}
		end

		return obj
	end
end

local function luaO_LexState(src) return {cmts = {}, line = 1, pos = 1, src = src} end

return {LexState = luaO_LexState, Node = luaO_Node}
