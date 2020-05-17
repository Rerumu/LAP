-- simple object constructors for nodes and states module
local luaO_Node = {}
local luaO_preNode = {}

function luaO_preNode.BinopExpr(op, lhs, rhs) return {operator = op, lhs = lhs, rhs = rhs} end

function luaO_preNode.CallMethodExpr(src, name, params)
	return {src = src, name = name, params = params}
end

function luaO_preNode.CallExpr(func, params) return {func = func, params = params} end

function luaO_preNode.IndexExpr(src, index) return {src = src, index = index} end

function luaO_preNode.LiteralExpr(tt, value) return {tt = tt, value = value} end

function luaO_preNode.NameExpr(name) return {name = name} end

function luaO_preNode.ParensExpr(value) return {value = value} end

function luaO_preNode.TableExpr(array, hash) return {array = array, hash = hash} end

function luaO_preNode.UnopExpr(op, rhs) return {operator = op, rhs = rhs} end

function luaO_preNode.BreakStat()
	return {} -- nothing lol
end

function luaO_preNode.DoStat(body) return {body = body} end

function luaO_preNode.ForIteratorStat(vars, params) return
	{vars = vars, params = params, body = nil} end

function luaO_preNode.ForRangeStat(var, limit, step)
	return {var = var, limit = limit, step = step, body = nil}
end

function luaO_preNode.FuncStat(name, params, body) return
	{name = name, params = params, body = body} end

function luaO_preNode.GotoStat(label) return {label = label} end

function luaO_preNode.IfStat(list, base) return {list = list, base = base} end

function luaO_preNode.LocalFuncStat(name, func) return {name = name, func = func} end

function luaO_preNode.LocalStat(names, values) return {names = names, values = values} end

function luaO_preNode.RepeatStat(cond, body) return {cond = cond, body = body} end

function luaO_preNode.ReturnStat(values) return {values = values} end

function luaO_preNode.WhileStat(cond, body) return {cond = cond, body = body} end

function luaO_preNode.LabelStat(label) return {label = label} end

function luaO_preNode.AssignStat(lhs, rhs) return {lhs = lhs, rhs = rhs} end

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
