
if io.slurp == nil then
    io.slurp = function(filename)
        local f = io.open(filename)
        local r = f.read(f, '*all')
        f.close(f)
        return r
    end
end

if io.dump == nil then
    io.dump = function(name, data)
        local val = io.open(name, "w")
        val.write(val, data)
        val.close(val)
    end
end

local fun = {}

local function unlistof(list, arr)
    if #list ~= 0 then
        arr[#arr + 1] = list[1]
        return unlistof(list[2], arr)
    else
        return arr
    end
end

local function fun_unlist(list)
    return unlistof(list, {})
end

local function fun_joinlist(arr)
    return table.concat(fun_unlist(arr))
end

local parser_pos = 1
local parser_line = 2
local parser_col = 3
local parser_src = 4
local parser_best = 5

local best_pos = 1
local best_line = 2
local best_col = 3

local function parser_new(src)
    return {1, 1, 1, src, {0, 1, 1}}
end

local function parser_advance(state, chr)
    local best = state[parser_best]
    if best[best_pos] < state[parser_pos] then
        best[best_pos] = state[parser_pos]
        best[best_line] = state[parser_line]
        best[best_col] = state[parser_col]
    end
    if chr == '\n' then
        return {state[parser_pos] + 1, state[parser_line] + 1, 1, state[parser_src], best}
    else
        return {state[parser_pos] + 1, state[parser_line], state[parser_col] + 1, state[parser_src], best}
    end
end

local function parser_any(state, ok, err)
    if state[parser_pos] <= string.len(state[parser_src]) then
        local chr = string.sub(state[parser_src], state[parser_pos], state[parser_pos])
        return ok(parser_advance(state, chr), chr)
    else
        return err(state, 'unexpected: end of file')
    end
end

local function parser_eof(state, ok, err)
    if state[parser_pos] > string.len(state[parser_src]) then
        return ok(state, nil)
    else
        return err(state, 
            'wanted the file to end (Ln ' .. state[parser_best][best_line] .. ', Col ' .. state[parser_best][best_col] .. ')')
    end
end

local function parser_accept(value)
    return function(state, ok, err)
        return ok(state, value)
    end
end

local function parser_cond(next, xcond)
    return function(state, ok, err)
        return next(state, function(state, data)
            if xcond(data) then
                return ok(state, data)
            else
                return err(state, 'cannot match')
            end
        end, function(state, msg)
            return err(state, msg)
        end)
    end
end

local function parser_exact(char)
    return function(state, ok, err)
        if state[parser_pos] <= string.len(state[parser_src]) then
            local chr = string.sub(state[parser_src], state[parser_pos], state[parser_pos])
            if chr == char then
                return ok(parser_advance(state, chr), chr)
            else
                return err(state, 'cannot match')
            end
        else
            return err(state, 'unexpected: end of file')
        end
    end
end

local function parser_notexact(char)
    return function(state, ok, err)
        if state[parser_pos] <= string.len(state[parser_src]) then
            local chr = string.sub(state[parser_src], state[parser_pos], state[parser_pos])
            if chr ~= char then
                return ok(parser_advance(state, chr), chr)
            else
                return err(state, 'cannot match')
            end
        else
            return err(state, 'unexpected: end of file')
        end
    end
end

local function parser_range(low, high)
    local low_byte = string.byte(low)
    local high_byte = string.byte(high)
    return function(state, ok, err)
        if state[parser_pos] <= string.len(state[parser_src]) then
            local chr = string.sub(state[parser_src], state[parser_pos], state[parser_pos])
            local byte = string.byte(chr)
            if low_byte <= byte and byte <= high_byte then
                return ok(parser_advance(state, chr), chr)
            else
                return err(state, 'cannot match range')
            end
        else
            return err(state, 'unexpected: end of file')
        end
    end
end

local function parser_first(...)
    local function more(opts, start)
        local first = opts[start]
        if start >= #opts then
            return first
        end
        local fnext = more(opts, start + 1)
        return function(state, ok, err)
            return first(state, ok, function(state2, msg1)
                return fnext(state, ok, function(state, msg2)
                    return err(state, 'cannot match either')
                end)
            end)
        end
    end
    return more({...}, 1)
end

local function parser_transform(xnext, func)
    return function(state, ok, err)
        return xnext(state, function(state, data)
            return ok(state, func(data))
        end, err)
    end
end

local function parser_cons(parse1, parse2)
    return function(state, ok, err)
        return parse1(state, function(state, data1)
            return parse2(state, function(state, data2)
                return ok(state, {data1, data2})
            end, err)
        end, err)
    end
end

local function parser_list0(next)
    local rest = nil
    local function more(state, ok, err)
        return rest(state, ok, function(state2, msg)
            return ok(state, {})
        end)
    end
    rest = parser_cons(next, more)
    return more
end

local function parser_list1(next)
    return parser_cons(next, parser_list0(next))
end

local function parser_skiponly(skip, read)
    return parser_transform(parser_cons(skip, read), function(data)
        return data[2]
    end)
end

local function parser_skips(skip, read)
    return parser_skiponly(parser_list0(skip), read)
end

local function parser_string(str)
    local ret = parser_accept({})
    local len = string.len(str)
    for i = 0, len - 1 do
        ret = parser_cons(parser_exact(string.sub(str, len - i, len - i)), ret)
    end
    return parser_transform(ret, fun_joinlist)
end

local function parser_listof(...)
    local tab = {...}
    local function more(head)
        local cur = tab[head]
        if cur == nil then
            return parser_accept({})
        else
            return parser_cons(cur, more(head + 1))
        end
    end
    return more(1)
end

local function parser_select(n, ...)
    return parser_transform(parser_listof(...), function(data)
        for i = 2, n do
            data = data[2]
        end
        return data[1]
    end)
end

local function parser_sep1(lis, sep)
    return parser_cons(lis, parser_list0(parser_select(2, sep, lis)))
end

local function parser_sep(lis, sep)
    return parser_first(parser_sep1(lis, sep), parser_accept({}))
end

local function aststr(ast)
    if type(ast) ~= 'table' then
        return tostring(ast)
    elseif ast.type ~= nil then
        local tab = {}
        tab[#tab + 1] = '('
        tab[#tab + 1] = ast.type
        for i = 1, #ast do
            tab[#tab + 1] = ' '
            tab[#tab + 1] = aststr(ast[i])
        end
        tab[#tab + 1] = ')'
        return table.concat(tab)
    else
        local tab = {}
        tab[#tab + 1] = '{'
        for i = 1, #ast do
            tab[#tab + 1] = ' '
            tab[#tab + 1] = aststr(ast[i])
        end
        tab[#tab + 1] = '}'
        return table.concat(tab)
    end
end

local lua = {}

lua.comment = parser_listof(parser_string('--'), parser_list0(parser_notexact('\n')))
lua.ws = parser_list0(parser_first(parser_exact(' '), parser_exact('\n'), parser_exact('\t'), parser_exact('\r'),
    lua.comment))

function lua.wrap(par)
    return parser_select(2, lua.ws, par, lua.ws)
end

local function makeast(type, pos, ...)
    return {
        type = type,
        pos = pos,
        ...
    }
end

function lua.ast(ast, ...)
    local next = lua.wrap(parser_listof(...))
    return function(state1, ok, err)
        return next(state1, function(state2, data1)
            local head = {
                line = state1.line,
                col = state1.col
            }
            local tail = {
                line = state2.line,
                col = state2.col
            }
            local pos = {
                head = head,
                tail = tail
            }
            local data2 = makeast(ast, pos)
            local datarr = fun_unlist(data1)
            for i = 1, #datarr do
                local val = datarr[i]
                if type(val) == 'table' and val.expand then
                    for i = 1, #val do
                        data2[#data2 + 1] = val[i]
                    end
                elseif type(val) ~= 'table' or not val.ignore then
                    data2[#data2 + 1] = val
                end
            end
            return ok(state2, data2)
        end, function(state, msg)
            return err(state, msg)
        end)
    end
end

function lua.delay(name)
    return function(state, ok, err)
        return lua[name](state, ok, err)
    end
end

function lua.ignore(par)
    return parser_transform(par, function(data)
        return {
            ignore = true
        }
    end)
end

function lua.maybe(par)
    return parser_first(par, parser_accept({
        ignore = true
    }))
end

local astlist = function(arg)
    local res = fun_unlist(arg)
    res.expand = true
    return res
end
local keywords = {'not', 'break', 'if', 'elseif', 'else', 'then', 'while', 'do', 'local', 'end', 'function', 'repeat',
                  'until', 'return', 'then', 'nil', 'true', 'false', 'in', 'for'}
local hashkeywords = {}
for i = 1, #keywords do
    hashkeywords[keywords[i]] = keywords[i]
end
local function isident(id)
    return hashkeywords[id] == nil
end
local function iskeyword(id)
    return hashkeywords[id] ~= nil
end

function lua.keyword(name)
    return lua.ignore(lua.wrap(parser_cond(parser_string(name), iskeyword)))
end

function lua.keywordliteral(name)
    return parser_cond(parser_string(name), iskeyword)
end

function lua.binop(child, names)
    local ops = parser_string(names[1])
    for i = 2, #names do
        ops = parser_first(ops, parser_string(names[i]))
    end
    ops = lua.wrap(ops)
    return parser_transform(lua.wrap(parser_cons(child, parser_list0(parser_cons(ops, child)))), function(data)
        local lhs = data[1]
        local rhs = fun_unlist(data[2])
        for i = 1, #rhs do
            local ent = rhs[i]
            local pos = {
                head = lhs.pos.head,
                tail = ent[2].pos.tail
            }
            lhs = makeast(ent[1], pos, lhs, ent[2])
        end
        return lhs
    end)
end

lua.lowerletter = parser_range('a', 'z')
lua.upperletter = parser_range('A', 'Z')
lua.digit = parser_range('0', '9')
lua.letter = parser_first(lua.lowerletter, lua.upperletter)
lua.digits = parser_cond(parser_transform(parser_list1(parser_first(lua.digit, parser_exact('.'))), fun_joinlist),
    function(s)
        local dots = 0
        for i = 1, string.len(s) do
            if string.sub(s, i, i) == '.' then
                dots = dots + 1
            end
        end
        return dots <= 1
    end)
lua.name = parser_transform(parser_cons(parser_first(lua.letter, parser_exact('_')),
    parser_list0(parser_first(lua.digit, lua.letter, parser_exact('_')))), fun_joinlist)

local function stringbody(wrap)
    return parser_transform(parser_select(2, parser_string(wrap),
        parser_list0(parser_first(parser_transform(parser_listof(parser_exact('\\'), parser_any), fun_joinlist),
            parser_notexact(wrap))), parser_exact(wrap)), fun_joinlist)
end

lua.string = lua.ast('string', parser_first(stringbody('"'), stringbody("'")))

lua.expr = lua.delay('expr')
lua.chunk = lua.delay('chunk')
lua.varargs = lua.ast('varargs', lua.ignore(parser_string('...')))
lua.literal = lua.ast('literal', parser_first(lua.varargs, lua.keywordliteral('nil'), lua.keywordliteral('false'),
    lua.keywordliteral('true')))
lua.number = lua.ast('number', lua.digits)
lua.ident = lua.ast('ident', parser_cond(lua.name, isident))
lua.params = lua.ast('params', lua.ignore(parser_exact('(')),
    parser_transform(parser_sep(parser_first(lua.varargs, lua.ident), parser_exact(',')), astlist),
    lua.ignore(parser_exact(')')))
lua.fieldnamed = lua.ast('fieldnamed', lua.ident, lua.ignore(parser_exact('=')), lua.expr)
lua.fieldnth = lua.ast('fieldnth', lua.expr)
lua.fieldvalue = lua.ast('fieldvalue', lua.ignore(parser_exact('[')), lua.expr, parser_exact(']'),
    lua.ignore(parser_exact('=')), lua.expr)
lua.field = parser_first(lua.fieldnamed, lua.fieldnth, lua.fieldvalue)
lua.table = lua.ast('table', lua.ignore(parser_exact('{')),
    parser_transform(parser_sep(lua.field, parser_exact(',')), astlist), lua.ignore(parser_exact('}')))
lua.lambda = lua.ast('lambda', lua.keyword('function'), lua.params, lua.chunk, lua.keyword('end'))
lua.parens = parser_select(2, parser_exact('('), lua.expr, parser_exact(')'))
lua.single = parser_first(lua.string, lua.number, lua.lambda, lua.ident, lua.table, lua.literal, lua.parens)
lua.args = parser_first(lua.ast('call', lua.string), lua.ast('call', lua.table),
    lua.ast('call', lua.ignore(parser_exact('(')),
        parser_transform(parser_sep(lua.expr, lua.wrap(parser_exact(','))), astlist), lua.ignore(parser_exact(')'))))
lua.index = lua.ast('index', lua.ignore(parser_exact('[')), lua.expr, lua.ignore(parser_exact(']')))
lua.dotindex = lua.ast('dotindex', lua.ignore(parser_exact('.')), lua.ident)
lua.methodcall = lua.ast('method', lua.ignore(parser_exact(':')), lua.ident, lua.args)
lua.postext = parser_first(lua.args, lua.index, lua.dotindex, lua.methodcall)
lua.post = lua.ast('postfix', lua.single, parser_transform(parser_list0(lua.postext), astlist))
lua.pre = parser_first(lua.ast('length', lua.ignore(parser_exact('#')), lua.post),
    lua.ast('negate', lua.ignore(parser_exact('-')), lua.post), lua.ast('not', lua.keyword('not'), lua.post), lua.post)

lua.powexpr = lua.binop(lua.pre, {'^'})
lua.mulexpr = lua.binop(lua.powexpr, {'*', '/', '%'})
lua.addexpr = lua.binop(lua.mulexpr, {'+', '-'})
lua.catexpr = lua.binop(lua.addexpr, {'..'})
lua.compare = lua.binop(lua.catexpr, {'<=', '>=', '==', '~=', '<', '>'})
lua.logic = lua.binop(lua.compare, {'and', 'or'})
lua.expr = lua.logic

lua.post1 = lua.ast('postfix', lua.single, parser_transform(parser_list1(lua.postext), astlist))

lua.idents = lua.ast('to', parser_transform(parser_sep1(lua.ident, parser_exact(',')), astlist))
lua.exprs = lua.ast('from', parser_transform(parser_sep1(lua.expr, parser_exact(',')), astlist))
lua.posts = lua.ast('to', parser_transform(parser_sep1(lua.post, parser_exact(',')), astlist))

lua.stmtlocalfunction = lua.ast('local', lua.keyword('local'), lua.keyword('function'), lua.ident,
    lua.ast('lambda', lua.params, lua.chunk), lua.keyword('end'))
lua.assigns = lua.ast('assign', lua.posts, lua.ignore(parser_exact('=')), lua.exprs)
lua.stmtlocal = lua.ast('local', lua.keyword('local'), lua.idents,
    lua.maybe(parser_select(2, parser_exact('='), lua.exprs)))
lua.ifelse = lua.ast('else', lua.keyword('else'), lua.chunk)
lua.ifelseif = lua.ast('case', lua.keyword('elseif'), lua.expr, lua.keyword('then'), lua.chunk)
lua.ifelseifs = parser_transform(parser_list0(lua.ifelseif), astlist)
lua.stmtif = lua.ast('cond', lua.keyword('if'), lua.ast('case', lua.expr, lua.keyword('then'), lua.chunk),
    lua.ifelseifs, lua.maybe(lua.ifelse), lua.keyword('end'))
lua.stmtwhile = lua.ast('while', lua.keyword('while'), lua.expr, lua.keyword('do'), lua.chunk, lua.keyword('end'))
lua.stmtfunction = lua.ast('function', lua.keyword('function'), lua.post1, lua.chunk, lua.keyword('end'))
lua.stmtfor = lua.ast('for', lua.keyword('for'), lua.ident, lua.ignore(parser_exact('=')), lua.expr,
    lua.ignore(parser_exact(',')), lua.expr, lua.maybe(parser_select(2, parser_exact(','), lua.expr)),
    lua.keyword('do'), lua.chunk, lua.keyword('end'))
lua.stmtforin = lua.ast('forin', lua.keyword('for'), lua.idents, lua.keyword('in'), lua.exprs, lua.keyword('do'),
    lua.chunk, lua.keyword('end'))
lua.stmtdo = parser_select(2, lua.keyword('do'), lua.chunk, lua.keyword('end'))
lua.stmtbreak = lua.ast('break', lua.keyword('break'))
lua.stmt = parser_first(lua.stmtbreak, lua.stmtif, lua.stmtforin, lua.stmtfor, lua.stmtlocalfunction, lua.stmtlocal,
    lua.stmtwhile, lua.stmtfunction, lua.assigns, lua.post1, lua.stmtdo)
lua.stmtreturn = lua.ast('return', lua.keyword('return'), lua.exprs)
lua.chunk = lua.ast('begin', parser_transform(parser_list0(parser_first(lua.stmt, parser_exact(';'))), astlist),
    lua.maybe(lua.stmtreturn), lua.ignore(parser_list0(parser_exact(';'))))

lua.langline = parser_listof(parser_exact('#'), parser_list0(parser_notexact('\n')))
lua.program = lua.ast('program', lua.ignore(lua.maybe(lua.langline)), lua.chunk, lua.ignore(parser_eof))

local function parse(par, str)
    local ret = {}
    local state = parser_new(str)
    par(state, function(state, data)
        ret.ok = true
        ret.ast = data
    end, function(state, msg)
        ret.ok = false
        ret.msg = msg
    end)
    return ret
end

local comp = {}

local function mangle(name)
    return 'local_' .. name
end

local ops = {}
ops['..'] = 'lua_concat'
ops['+'] = 'lua_add'
ops['-'] = 'lua_sub'
ops['*'] = 'lua_pow'
ops['/'] = 'lua_div'
ops['%'] = 'lua_mod'
ops['^'] = 'lua_pow'
ops['<'] = 'lua_lt'
ops['>'] = 'lua_gt'
ops['<='] = 'lua_le'
ops['>='] = 'lua_ge'
ops['=='] = 'lua_eq'
ops['~='] = 'lua_ne'

local function unpostfix(ast)
    if ast.type ~= 'postfix' then
        return ast
    end
    local tab = ast[1]
    for i = 2, #ast do
        local ent = ast[i]
        tab = makeast(ent.type, ent.pos, tab)
        for j = 1, #ent do
            tab[j + 1] = ent[j]
        end
    end
    return tab
end

local ntables = 1

local function syntaxstr(ast, vars)
    -- print(aststr(ast))
    if type(ast) == 'string' then
        local chars = {}
        for i = 1, string.len(ast) do
            local chr = string.sub(ast, i, i)
            if chr == '"' then
                chars[i] = '\\"'
            else
                chars[i] = chr
            end
        end
        return '["' .. table.concat(chars) .. '"]'
    elseif ast.type == 'literal' then
        if ast[1] == 'true' then
            return '[true]'
        elseif ast[1] == 'false' then
            return '[false]'
        elseif ast[1] == 'nil' then
            return '[undefined]'
        elseif type(ast[1]) == 'table' and ast[1].type == 'varargs' then
            return 'varargs'
        else
            error('bad literal: ' .. tostring(ast[1]))
        end
    elseif ast.type == 'not' then
        return '[!lua_toboolean(lua_first(' .. syntaxstr(ast[1], vars) .. '))]'
    elseif ast.type == 'string' then
        return syntaxstr(ast[1], vars)
    elseif ast.type == 'or' then
        return '[await lua_or(lua_first(' .. syntaxstr(ast[1], vars) .. '),async ()=>lua_first(' .. syntaxstr(ast[2], vars) ..
                   '))]'
    elseif ast.type == 'and' then
        return
            '[await lua_and(lua_first(' .. syntaxstr(ast[1], vars) .. '),async ()=>lua_first(' .. syntaxstr(ast[2], vars) ..
                '))]'
    elseif ast.type == 'table' then
        local fun = {}
        fun[#fun + 1] = '(await (async ()=>{var n=0,t=Object.create(null);'
        for i = 1, #ast do
            local field = ast[i]
            if field.type == 'fieldnamed' then
                fun[#fun + 1] = 't["'
                fun[#fun + 1] = field[1][1]
                fun[#fun + 1] = '"]=lua_first('
                fun[#fun + 1] = syntaxstr(field[2], vars)
                fun[#fun + 1] = ');'
            elseif field.type == 'fieldnth' then
                if i ~= #ast then
                    fun[#fun + 1] = 't[++n]=lua_first('
                    fun[#fun + 1] = syntaxstr(field[1], vars)
                    fun[#fun + 1] = ');'
                else
                    fun[#fun + 1] = 'for(const v of '
                    fun[#fun + 1] = syntaxstr(field[1], vars)
                    fun[#fun + 1] = '){t[++n]=v;}'
                end
            elseif field.type == 'fieldvalue' then
                fun[#fun + 1] = 't[lua_first('
                fun[#fun + 1] = syntaxstr(field[1], vars)
                fun[#fun + 1] = ')]=lua_first('
                fun[#fun + 1] = syntaxstr(field[2], vars)
                fun[#fun + 1] = ');'
            end
        end
        fun[#fun + 1] = 'return [t];})())'
        return table.concat(fun)
    elseif ast.type == 'while' then
        return 'while(lua_toboolean(' .. syntaxstr(ast[1], vars) .. ')) {' .. syntaxstr(ast[2], vars) .. '}'
    elseif ast.type == 'for' then
        local cvar = vars[#vars]
        cvar[#cvar + 1] = ast[1][1]
        cvar[ast[1][1]] = false
        local inrange = {}
        for i = 2, #ast - 1 do
            inrange[#inrange + 1] = 'lua_first(' .. syntaxstr(ast[i], vars) .. ')'
        end
        if inrange[3] == nil then
            inrange[3] = '1'
        end
        local start = mangle(ast[1][1])
        local body = syntaxstr(ast[#ast], vars)
        return
            'for (let i=' .. inrange[1] .. ',m=' .. inrange[2] .. ',c=' .. inrange[3] .. ';i<=m;i+=c){var ' .. start ..
                '=i;' .. body .. '}'
    elseif ast.type == 'ident' then
        for i = 1, #vars do
            local level = vars[i]
            for j = 1, #level do
                if level[j] == ast[1] then
                    return '[' .. mangle(ast[1]) .. ']'
                end
            end
        end
        return '[lua_index(local__ENV,"' .. ast[1] .. '")]'
    elseif ast.type == 'break' then
        return 'break'
    elseif ast.type == 'number' then
        return '[' .. tostring(ast[1]) .. ']'
    elseif ast.type == 'program' then
        local tab = {}
        tab[#tab + 1] = '(async ()=>{'
        for i = 1, #ast do
            tab[#tab + 1] = syntaxstr(ast[i], vars)
            tab[#tab + 1] = ';\n'
        end
        tab[#tab + 1] = '})();'
        return table.concat(tab)
    elseif ast.type == 'begin' then
        local tab = {}
        vars[#vars + 1] = {}
        tab[#tab + 1] = '{'
        for i = 1, #ast do
            tab[#tab + 1] = syntaxstr(ast[i], vars)
            tab[#tab + 1] = ';\n'
        end
        tab[#tab + 1] = '}';
        vars[#vars] = nil
        return table.concat(tab)
    elseif ast.type == 'postfix' then
        return syntaxstr(unpostfix(ast), vars)
    elseif ast.type == 'method' then
        local apply = {}
        apply[#apply + 1] = '(await lua_apply('
        apply[#apply + 1] = 'lua_first('
        apply[#apply + 1] = syntaxstr(ast[1], vars)
        apply[#apply + 1] = '),"'
        apply[#apply + 1] = ast[2][1]
        apply[#apply + 1] = '",'
        local call = ast[#ast]
        for i = 1, #call do
            if i == #call then
                apply[#apply + 1] = '...'
                apply[#apply + 1] = syntaxstr(call[i], vars)
            else
                apply[#apply + 1] = 'lua_first('
                apply[#apply + 1] = syntaxstr(call[i], vars)
                apply[#apply + 1] = '),'
            end
        end
        apply[#apply + 1] = '))'
        return table.concat(apply)
    elseif ast.type == 'call' then
        local apply = {}
        apply[#apply + 1] = '(await lua_call('
        for i = 1, #ast do
            if i == #ast and i > 1 then
                apply[#apply + 1] = '...'
                apply[#apply + 1] = syntaxstr(ast[i], vars)
            else
                apply[#apply + 1] = 'lua_first('
                apply[#apply + 1] = syntaxstr(ast[i], vars)
                apply[#apply + 1] = '),'
            end
        end
        apply[#apply + 1] = '))'
        return table.concat(apply)
    elseif ast.type == 'dotindex' then
        return '[lua_index(lua_first(' .. syntaxstr(ast[1], vars) .. '),"' .. ast[2][1] .. '")]'
    elseif ast.type == 'index' then
        return '[lua_index(lua_first(' .. syntaxstr(ast[1], vars) .. '),lua_first(' .. syntaxstr(ast[2], vars) .. '))]'
    elseif ast.type == 'assign' then
        local targets = ast[1]
        local exprs = ast[2]
        local parts = {}
        parts[#parts + 1] = '(await (async ()=>{var parts=['
        for i = 1, #exprs do
            if i ~= #exprs then
                parts[#parts + 1] = 'lua_first('
                parts[#parts + 1] = syntaxstr(exprs[i], vars)
                parts[#parts + 1] = '),'
            else
                parts[#parts + 1] = '...'
                parts[#parts + 1] = syntaxstr(exprs[i], vars)
            end
        end
        parts[#parts + 1] = '];'
        for i = 1, #targets do
            local target = unpostfix(targets[i])
            if target.type == 'ident' then
                local global = true
                for i = 1, #vars do
                    local level = vars[i]
                    for j = 1, #level do
                        if level[j] == target[1] then
                            parts[#parts + 1] = mangle(target[1])
                            parts[#parts + 1] = '=parts.shift();'
                            global = false
                        end
                    end
                end
                if global then
                    parts[#parts + 1] = 'lua_set(local__ENV,"'
                    parts[#parts + 1] = target[1]
                    parts[#parts + 1] = '",parts.shift());'
                end
            elseif target.type == 'dotindex' then
                parts[#parts + 1] = 'lua_set(lua_first('
                parts[#parts + 1] = syntaxstr(target[1], vars)
                parts[#parts + 1] = '),"'
                parts[#parts + 1] = target[2][1]
                parts[#parts + 1] = '",parts.shift());'
            elseif target.type == 'index' then
                parts[#parts + 1] = 'lua_set(lua_first('
                parts[#parts + 1] = syntaxstr(target[1], vars)
                parts[#parts + 1] = '),lua_first('
                parts[#parts + 1] = syntaxstr(target[2], vars)
                parts[#parts + 1] = '),parts.shift());'
            else
                error('assign:' .. target.type)
            end
        end
        parts[#parts + 1] = '})())'
        return table.concat(parts)
    elseif ast.type == 'function' then
        local target = ast[1]
        local callargs = target[#target]
        local args = makeast('args', callargs.pos)
        for i = 1, #callargs do
            local val = unpostfix(callargs[i])
            if val.type == 'literal' then
                args[i] = makeast('varargs', val.pos)
            else
                args[i] = val
            end
        end
        local tmp = makeast('assign', ast[2].pos, makeast('to', ast[1].pos, unpostfix(target)[1]),
            makeast('from', ast[2].pos, makeast('lambda', ast[2].pos, args, ast[2])))
        return syntaxstr(tmp, vars)
    elseif ast.type == 'local' then
        local idents = ast[1]
        local exprs = ast[2]
        local cvar = vars[#vars]
        if idents.type == 'ident' then
            cvar[#cvar + 1] = idents[1]
            cvar[idents[1]] = true
            return 'let ' .. mangle(idents[1]) .. '=lua_first(' .. syntaxstr(exprs, vars) .. ')'
        else
            local tab = {}
            tab[#tab + 1] = 'var parts=['
            for i = 1, #exprs do
                if i == #exprs then
                    tab[#tab + 1] = '...'
                    tab[#tab + 1] = syntaxstr(exprs[i], vars)
                else
                    tab[#tab + 1] = syntaxstr(exprs[i], vars)
                    tab[#tab + 1] = ','
                end
            end
            tab[#tab + 1] = '];'
            for i = 1, #idents do
                local name = idents[i][1]
                cvar[#cvar + 1] = name
                cvar[name] = true
                tab[#tab + 1] = 'var '
                tab[#tab + 1] = mangle(name)
                tab[#tab + 1] = '=parts.shift();'
            end
            return table.concat(tab)
        end
    elseif ast.type == 'lambda' then
        local scope = {}
        vars[#vars + 1] = scope
        local parts = {}
        parts[#parts + 1] = '[async function(...varargs){if(this!=null)varargs.unshift(this);'
        for i = 1, #ast[1] do
            local arg = ast[1][i]
            if arg.type ~= 'varargs' then
                local name = arg[1]
                scope[#scope + 1] = name
                scope[name] = true
                parts[#parts + 1] = 'var '
                parts[#parts + 1] = mangle(name)
                parts[#parts + 1] = '=varargs.shift();'
            end
        end
        parts[#parts + 1] = syntaxstr(ast[2], vars)
        parts[#parts + 1] = 'return[];}]'
        vars[#vars] = nil
        return table.concat(parts)
    elseif ast.type == 'return' then
        local parts = {}
        parts[#parts + 1] = '{return['
        for i = 1, #ast[1] do
            if i ~= #ast[1] then
                parts[#parts + 1] = 'lua_first('
                parts[#parts + 1] = syntaxstr(ast[1][i], vars)
                parts[#parts + 1] = '),'
            else
                parts[#parts + 1] = '...'
                parts[#parts + 1] = syntaxstr(ast[1][i], vars)
            end
        end
        parts[#parts + 1] = '];}'
        return table.concat(parts)
    elseif ast.type == 'cond' then
        local cond = {}
        for i = 1, #ast do
            local part = ast[i]
            if part.type == 'case' then
                if i == 1 then
                    cond[#cond + 1] = 'if(lua_first('
                    cond[#cond + 1] = syntaxstr(part[1], vars)
                    cond[#cond + 1] = ')){'
                    cond[#cond + 1] = syntaxstr(part[2], vars)
                    cond[#cond + 1] = '}'
                else
                    cond[#cond + 1] = 'else if(lua_first('
                    cond[#cond + 1] = syntaxstr(part[1], vars)
                    cond[#cond + 1] = ')){'
                    cond[#cond + 1] = syntaxstr(part[2], vars)
                    cond[#cond + 1] = '}'
                end
            elseif part.type == 'else' then
                cond[#cond + 1] = 'else{'
                cond[#cond + 1] = syntaxstr(part[1], vars)
                cond[#cond + 1] = '}'
            else
                error('ast.type = ' .. part.type)
            end
        end
        return table.concat(cond)
    elseif ast.type == 'negate' then
        return '[lua_unm(lua_first(' .. syntaxstr(ast[1], vars) .. '))]'
    elseif ast.type == 'length' then
        return '[lua_length(lua_first(' .. syntaxstr(ast[1], vars) .. '))]'
    elseif ast.type == 'varargs' then
        return 'varargs'
    elseif ops[ast.type] ~= nil then
        local parts = {}
        parts[#parts + 1] = '[await '
        parts[#parts + 1] = ops[ast.type]
        parts[#parts + 1] = '(lua_first('
        parts[#parts + 1] = syntaxstr(ast[1], vars)
        parts[#parts + 1] = '),lua_first('
        parts[#parts + 1] = syntaxstr(ast[2], vars)
        parts[#parts + 1] = '))]'
        return table.concat(parts)
    else
        error('ast = ' .. aststr(ast))
    end
end

local infile = nil
local outfile = nil
for i = 1, #arg do
    local cur = arg[i]
    if infile == nil then
        infile = cur
    elseif outfile == nil then
        outfile = cur
    else
        print('error: too many args')
    end
end

local slurp = io.slurp
local src = slurp(arg[1])
local res = parse(lua.program, src)
if res.ok == true then
    local str = syntaxstr(res.ast, {{"_ENV"}})
    local pre = slurp('prelude.js')
    local finalstr = pre .. str
    if outfile ~= nil then
        io.dump(outfile, finalstr)
    elseif eval then
        eval(finalstr)
    else
        print('error: no output provided')
    end
else
    error(res.msg)
end
