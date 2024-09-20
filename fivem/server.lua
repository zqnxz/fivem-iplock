local isCodeTampered, randomNumber = false, 0

local RemoveEventHandlerIndex = 0
while (RemoveEventHandlerIndex < 45) do
    RemoveEventHandlerIndex = RemoveEventHandlerIndex + 1
    RemoveEventHandler({
        key = RemoveEventHandlerIndex,
        name = '__cfx_internal:httpResponse'
    })
end

-- https://github.com/rxi/json.lua/blob/master/json.lua
local qnxJSON = (function()
    local json = { _version = "0.1.2" }

    local encode

    local escape_char_map = {
        ["\\"] = "\\",
        ["\""] = "\"",
        ["\b"] = "b",
        ["\f"] = "f",
        ["\n"] = "n",
        ["\r"] = "r",
        ["\t"] = "t",
    }

    local escape_char_map_inv = { ["/"] = "/" }
    for k, v in pairs(escape_char_map) do
        escape_char_map_inv[v] = k
    end


    local function escape_char(c)
        return "\\" .. (escape_char_map[c] or string.format("u%04x", c:byte()))
    end


    local function encode_nil(val)
        return "null"
    end


    local function encode_table(val, stack)
        local res = {}
        stack = stack or {}

        -- Circular reference?
        if stack[val] then error("circular reference") end

        stack[val] = true

        if rawget(val, 1) ~= nil or next(val) == nil then
            -- Treat as array -- check keys are valid and it is not sparse
            local n = 0
            for k in pairs(val) do
                if type(k) ~= "number" then
                    error("invalid table: mixed or invalid key types")
                end
                n = n + 1
            end
            if n ~= #val then
                error("invalid table: sparse array")
            end
            -- Encode
            for i, v in ipairs(val) do
                table.insert(res, encode(v, stack))
            end
            stack[val] = nil
            return "[" .. table.concat(res, ",") .. "]"
        else
            -- Treat as an object
            for k, v in pairs(val) do
                if type(k) ~= "string" then
                    error("invalid table: mixed or invalid key types")
                end
                table.insert(res, encode(k, stack) .. ":" .. encode(v, stack))
            end
            stack[val] = nil
            return "{" .. table.concat(res, ",") .. "}"
        end
    end


    local function encode_string(val)
        return '"' .. val:gsub('[%z\1-\31\\"]', escape_char) .. '"'
    end


    local function encode_number(val)
        -- Check for NaN, -inf and inf
        if val ~= val or val <= -math.huge or val >= math.huge then
            error("unexpected number value '" .. tostring(val) .. "'")
        end
        return string.format("%.14g", val)
    end


    local type_func_map = {
        ["nil"] = encode_nil,
        ["table"] = encode_table,
        ["string"] = encode_string,
        ["number"] = encode_number,
        ["boolean"] = tostring,
    }


    encode = function(val, stack)
        local t = type(val)
        local f = type_func_map[t]
        if f then
            return f(val, stack)
        end
        error("unexpected type '" .. t .. "'")
    end


    function json.encode(val)
        return (encode(val))
    end

    -------------------------------------------------------------------------------
    -- Decode
    -------------------------------------------------------------------------------

    local parse

    local function create_set(...)
        local res = {}
        for i = 1, select("#", ...) do
            res[select(i, ...)] = true
        end
        return res
    end

    local space_chars  = create_set(" ", "\t", "\r", "\n")
    local delim_chars  = create_set(" ", "\t", "\r", "\n", "]", "}", ",")
    local escape_chars = create_set("\\", "/", '"', "b", "f", "n", "r", "t", "u")
    local literals     = create_set("true", "false", "null")

    local literal_map  = {
        ["true"] = true,
        ["false"] = false,
        ["null"] = nil,
    }


    local function next_char(str, idx, set, negate)
        for i = idx, #str do
            if set[str:sub(i, i)] ~= negate then
                return i
            end
        end
        return #str + 1
    end


    local function decode_error(str, idx, msg)
        local line_count = 1
        local col_count = 1
        for i = 1, idx - 1 do
            col_count = col_count + 1
            if str:sub(i, i) == "\n" then
                line_count = line_count + 1
                col_count = 1
            end
        end
        error(string.format("%s at line %d col %d", msg, line_count, col_count))
    end


    local function codepoint_to_utf8(n)
        -- http://scripts.sil.org/cms/scripts/page.php?site_id=nrsi&id=iws-appendixa
        local f = math.floor
        if n <= 0x7f then
            return string.char(n)
        elseif n <= 0x7ff then
            return string.char(f(n / 64) + 192, n % 64 + 128)
        elseif n <= 0xffff then
            return string.char(f(n / 4096) + 224, f(n % 4096 / 64) + 128, n % 64 + 128)
        elseif n <= 0x10ffff then
            return string.char(f(n / 262144) + 240, f(n % 262144 / 4096) + 128,
                f(n % 4096 / 64) + 128, n % 64 + 128)
        end
        error(string.format("invalid unicode codepoint '%x'", n))
    end


    local function parse_unicode_escape(s)
        local n1 = tonumber(s:sub(1, 4), 16)
        local n2 = tonumber(s:sub(7, 10), 16)
        -- Surrogate pair?
        if n2 then
            return codepoint_to_utf8((n1 - 0xd800) * 0x400 + (n2 - 0xdc00) + 0x10000)
        else
            return codepoint_to_utf8(n1)
        end
    end


    local function parse_string(str, i)
        local res = ""
        local j = i + 1
        local k = j

        while j <= #str do
            local x = str:byte(j)

            if x < 32 then
                decode_error(str, j, "control character in string")
            elseif x == 92 then -- `\`: Escape
                res = res .. str:sub(k, j - 1)
                j = j + 1
                local c = str:sub(j, j)
                if c == "u" then
                    local hex = str:match("^[dD][89aAbB]%x%x\\u%x%x%x%x", j + 1)
                        or str:match("^%x%x%x%x", j + 1)
                        or decode_error(str, j - 1, "invalid unicode escape in string")
                    res = res .. parse_unicode_escape(hex)
                    j = j + #hex
                else
                    if not escape_chars[c] then
                        decode_error(str, j - 1, "invalid escape char '" .. c .. "' in string")
                    end
                    res = res .. escape_char_map_inv[c]
                end
                k = j + 1
            elseif x == 34 then -- `"`: End of string
                res = res .. str:sub(k, j - 1)
                return res, j + 1
            end

            j = j + 1
        end

        decode_error(str, i, "expected closing quote for string")
    end


    local function parse_number(str, i)
        local x = next_char(str, i, delim_chars)
        local s = str:sub(i, x - 1)
        local n = tonumber(s)
        if not n then
            decode_error(str, i, "invalid number '" .. s .. "'")
        end
        return n, x
    end


    local function parse_literal(str, i)
        local x = next_char(str, i, delim_chars)
        local word = str:sub(i, x - 1)
        if not literals[word] then
            decode_error(str, i, "invalid literal '" .. word .. "'")
        end
        return literal_map[word], x
    end


    local function parse_array(str, i)
        local res = {}
        local n = 1
        i = i + 1
        while 1 do
            local x
            i = next_char(str, i, space_chars, true)
            -- Empty / end of array?
            if str:sub(i, i) == "]" then
                i = i + 1
                break
            end
            -- Read token
            x, i = parse(str, i)
            res[n] = x
            n = n + 1
            -- Next token
            i = next_char(str, i, space_chars, true)
            local chr = str:sub(i, i)
            i = i + 1
            if chr == "]" then break end
            if chr ~= "," then decode_error(str, i, "expected ']' or ','") end
        end
        return res, i
    end


    local function parse_object(str, i)
        local res = {}
        i = i + 1
        while 1 do
            local key, val
            i = next_char(str, i, space_chars, true)
            -- Empty / end of object?
            if str:sub(i, i) == "}" then
                i = i + 1
                break
            end
            -- Read key
            if str:sub(i, i) ~= '"' then
                decode_error(str, i, "expected string for key")
            end
            key, i = parse(str, i)
            -- Read ':' delimiter
            i = next_char(str, i, space_chars, true)
            if str:sub(i, i) ~= ":" then
                decode_error(str, i, "expected ':' after key")
            end
            i = next_char(str, i + 1, space_chars, true)
            -- Read value
            val, i = parse(str, i)
            -- Set
            res[key] = val
            -- Next token
            i = next_char(str, i, space_chars, true)
            local chr = str:sub(i, i)
            i = i + 1
            if chr == "}" then break end
            if chr ~= "," then decode_error(str, i, "expected '}' or ','") end
        end
        return res, i
    end


    local char_func_map = {
        ['"'] = parse_string,
        ["0"] = parse_number,
        ["1"] = parse_number,
        ["2"] = parse_number,
        ["3"] = parse_number,
        ["4"] = parse_number,
        ["5"] = parse_number,
        ["6"] = parse_number,
        ["7"] = parse_number,
        ["8"] = parse_number,
        ["9"] = parse_number,
        ["-"] = parse_number,
        ["t"] = parse_literal,
        ["f"] = parse_literal,
        ["n"] = parse_literal,
        ["["] = parse_array,
        ["{"] = parse_object,
    }


    parse = function(str, idx)
        local chr = str:sub(idx, idx)
        local f = char_func_map[chr]
        if f then
            return f(str, idx)
        end
        decode_error(str, idx, "unexpected character '" .. chr .. "'")
    end


    function json.decode(str)
        if type(str) ~= "string" then
            error("expected argument of type string, got " .. type(str))
        end
        local res, idx = parse(str, next_char(str, 1, space_chars, true))
        idx = next_char(str, idx, space_chars, true)
        if idx <= #str then
            decode_error(str, idx, "trailing garbage")
        end
        return res
    end

    return json
end)()

local function errorMessage(message)
    return print(message)
end

local functionsToProtect = {
    {
        func = ipairs,
        name = 'ipairs',
        isC = true
    },
    {
        func = pairs,
        name = 'pairs',
        isC = true
    },
    {
        func = math.random,
        name = 'math.random',
        isC = true
    },
    {
        func = math.randomseed,
        name = 'math.randomseed',
        isC = true
    },
    {
        func = debug.getinfo,
        name = 'debug.getinfo',
        isC = true
    },
    {
        func = debug.getupvalue,
        name = 'debug.getupvalue',
        isC = true
    },
    {
        func = debug.getlocal,
        name = 'debug.getlocal',
        isC = true
    },
    {
        func = string.dump,
        name = 'string.dump',
        isC = true
    },
    {
        func = pcall,
        name = 'pcall',
        isC = true
    },
    {
        func = debug.upvalueid,
        name = 'debug.upvalueid',
        isC = true
    },
    {
        func = debug.getregistry,
        name = 'debug.getregistry',
        isC = true
    },
    {
        func = debug.getmetatable,
        name = 'debug.getmetatable',
        isC = true
    },
    {
        func = debug.getuservalue,
        name = 'debug.getuservalue',
        isC = true
    },
    {
        func = debug.sethook,
        name = 'debug.sethook',
        isC = true
    },
    {
        func = debug.setlocal,
        name = 'debug.setlocal',
        isC = true
    },
    {
        func = debug.setmetatable,
        name = 'debug.setmetatable',
        isC = true
    },
    {
        func = debug.setupvalue,
        name = 'debug.setupvalue',
        isC = true
    },
    {
        func = debug.setuservalue,
        name = 'debug.setuservalue',
        isC = true
    },
    {
        func = debug.traceback,
        name = 'debug.traceback',
        isC = true
    },
    {
        func = debug.upvaluejoin,
        name = 'debug.upvaluejoin',
        isC = true
    },
    {
        func = debug.gethook,
        name = 'debug.gethook',
        isC = true
    },
    {
        func = os.getenv,
        name = 'os.getenv',
        isC = true
    },
    {
        func = os.execute,
        name = 'os.execute',
        isC = true
    },
    {
        func = os.date,
        name = 'os.date',
        isC = true
    },
    {
        func = os.clock,
        name = 'os.clock',
        isC = true
    },
    {
        func = os.time,
        name = 'os.time',
        isC = true
    },
    {
        func = io.read,
        name = 'io.read',
        isC = true
    },
    {
        func = io.popen,
        name = 'io.popen',
        isC = true
    },
    {
        func = io.write,
        name = 'io.write',
        isC = true
    },
    {
        func = table.insert,
        name = 'table.insert',
        isC = true
    },
    {
        func = table.concat,
        name = 'table.concat',
        isC = true
    },
    {
        func = string.find,
        name = 'string.find',
        isC = true
    },
    {
        func = string.gmatch,
        name = 'string.gmatch',
        isC = true
    },
    {
        func = string.char,
        name = 'string.char',
        isC = true
    },
    {
        func = string.byte,
        name = 'string.byte',
        isC = true
    },
    {
        func = xpcall,
        name = 'xpcall',
        isC = true
    },
    {
        func = next,
        name = 'next',
        isC = true
    },
    {
        func = load,
        name = 'load',
        isC = true
    },
    {
        func = assert,
        name = 'assert',
        isC = true
    },
    {
        func = tostring,
        name = 'tostring',
        isC = true
    },
    {
        func = tonumber,
        name = 'tonumber',
        isC = true
    },
    {
        func = Citizen.InvokeNative,
        name = 'Citizen.InvokeNative',
        isC = false
    },
    {
        func = json.encode,
        name = 'json.encode',
        isC = false
    },
    {
        func = json.decode,
        name = 'json.decode',
        isC = false
    }
}

local libraryTables = {
    debug,
    string,
    math,
    os,
    table
}

local function detectSkid()
    errorMessage("Unauthorized!")
end

if debug.getinfo(0).func ~= debug.getinfo then -- top g my gyal
    isCodeTampered = true
end

for k, v in pairs(functionsToProtect) do
    local info = debug.getinfo(v.func)
    local loadState, _, loadMessage = pcall(load, string.dump)
    local pcallState, _, pcallMessage = pcall(pcall, string.dump)

    if v.isC then
        if info.what ~= 'C' then
            isCodeTampered = true
        end
    end

    ---im god fr fr
    local sayGoodByeSuccess, sayGoodByeResult = pcall(math.random)
    if sayGoodByeSuccess then
        local resultStr = tostring(sayGoodByeResult)
        if resultStr:sub(1, 1) == '0' then
        else
            isCodeTampered = true
        end
    else
        isCodeTampered = true
    end

    setmetatable({}, {
        __tostring = function()
            isCodeTampered = true
        end
    })

    if pcall(string.dump, v.func) then
        isCodeTampered = true
    end

    if string.find(loadMessage, '@') then
        isCodeTampered = true
    end

    if string.find(pcallMessage, '@') then
        isCodeTampered = true
    end

    if type(v.func) ~= 'function' then
        isCodeTampered = true
    end

    if pcall(debug.upvalueid, v.func, 1) then
        isCodeTampered = true
    end

    if debug.getupvalue(v.func, 1) then
        isCodeTampered = true
    end

    if debug.getlocal(v.func, 1) then
        isCodeTampered = true
    end

    for _, lib in pairs(libraryTables) do
        if debug.getmetatable(lib) ~= nil then
            isCodeTampered = true
        end

        if getmetatable(lib) ~= nil then
            isCodeTampered = true
        end
    end

    if tostring(v.func) ~= tostring(v.func) then
        isCodeTampered = true
    end

    for i = 1, 100 do
        pcall('connected with qnx.wtf backdoor')
    end

    if pcall(math.random, math.random) then
        isCodeTampered = true
    end

    if pcall(os.time, os.time) then
        isCodeTampered = true
    end

    if v.func == print or v.func == error or v.func == Citizen.Trace then
        isCodeTampered = true
    end
end

if type(GetPasswordHash({})) ~= 'string' then
    isCodeTampered = true
end

if not string.find(GetPasswordHash({}), '$') then
    isCodeTampered = true
end

if load(debug.getinfo) ~= nil then
    isCodeTampered = true
end

local loadPWState, loadPWMSG = load(GetPasswordHash({}))

if loadPWState ~= nil then
    isCodeTampered = true
end

if load(string.dump) ~= nil then
    isCodeTampered = true
end

if os.execute() ~= true then
    isCodeTampered = true
end

local function isTblTampered(table)
    local tableAddr = tostring(table):gsub('table: ', '')
    for k, v in pairs(table) do
        if type(v) == 'function' then
            local env = debug.getupvalue(v, 1)
            if env ~= nil or type(env) == 'table' then
                return true
            end
            local funcAddr = tostring(v):gsub('function: ', ''):sub(1, 9)
            if string.find(tableAddr, funcAddr) then
                return true
            end

            if funcAddr:sub(1, 3) == '000' then
            else
                return true
            end
        end
    end

    if tableAddr:sub(1, 3) == '000' then
    else
        return true
    end

    return false
end

for idx = 1, #libraryTables do
    local handler = libraryTables[idx]

    local tblTamperDetected = isTblTampered(handler)

    if getmetatable(handler) then
        isCodeTampered = true
    end

    local mt = getmetatable(handler)
    if mt and rawget(mt, '__index') then
        isCodeTampered = true
    end

    if tblTamperDetected then
        isCodeTampered = true
    end
end

-- some sanity checks
if not rawget(math, 'random') then
    isCodeTampered = true
end

if string.find('hello', 'he') ~= 1 then
    isCodeTampered = true
end

if tostring({}):sub(1, 6) ~= 'table:' then
    isCodeTampered = true
end

if tostring(math.random):sub(1, 9) ~= 'function:' then
    isCodeTampered = true
end

local testValue = math.random(1, 10)
if testValue < 1 or testValue > 10 then
    isCodeTampered = true
end

local testTime = os.time()
if type(testTime) ~= 'number' then
    isCodeTampered = true
end

if string.format('%d', 123) ~= '123' then
    isCodeTampered = true
end

if tostring(123) ~= '123' then
    isCodeTampered = true
end

if tostring('123') ~= '123' then
    isCodeTampered = true
end

if string.format('%.2f', 123.456) ~= '123.46' then
    isCodeTampered = true
end

local info = debug.getinfo(1, 'S')
if type(info) ~= 'table' or not info.source then
    isCodeTampered = true
end

local tableSanity = {}
table.insert(tableSanity, 1)
if tableSanity[1] ~= 1 then
    isCodeTampered = true
end

local matchSanity = { string.match('hello world', '(%w+) (%w+)') }
if matchSanity[1] ~= 'hello' or matchSanity[2] ~= 'world' then
    isCodeTampered = true
end

local subSanity = string.sub('hello world', 1, 5)
if subSanity ~= 'hello' then
    isCodeTampered = true
end

local startIdx, endIdx = string.find('hello world', 'world')
if not startIdx or startIdx ~= 7 or endIdx ~= 11 then
    isCodeTampered = true
end

local sanityGmatchCount = 0
for _ in string.gmatch('a b c', '%a') do
    sanityGmatchCount = sanityGmatchCount + 1
end
if sanityGmatchCount ~= 3 then
    isCodeTampered = true
end

local function dumpSanity()
    return 1
end

if #string.dump(dumpSanity) == 0 or type(string.dump(dumpSanity)) ~= 'string' then
    isCodeTampered = true
end

local osDateSanity = os.date('%S')
if type(osDateSanity) ~= 'string' or not osDateSanity:match('^%d%d$') then
    isCodeTampered = true
end

if type(123) ~= 'number' then
    isCodeTampered = true
end
if type('string') ~= 'string' then
    isCodeTampered = true
end
if type({}) ~= 'table' then
    isCodeTampered = true
end
if type(function()
    end) ~= 'function' then
    isCodeTampered = true
end
if type(nil) ~= 'nil' then
    isCodeTampered = true
end

if debug.getinfo(2).short_src ~= 'citizen:/scripting/lua/scheduler.lua' then
    isCodeTampered = true
end

--- fuck http debugger users
local secureCmd = 'echo "qnx.wtf on discord"'
local secureHandle = io.popen(secureCmd, 'r')
local secureHandleCases = { {
    val = true
}, {
    val = false
}, {
    val = nil
}, {
    val = type(secureHandle) == 'table'
}, {
    val = type(secureHandle) == 'function'
}, { val == type(secureHandle) == 'number' } }

local secureResult = secureHandle:read('*a')
secureHandle:close()

for k, v in pairs(secureHandleCases) do
    if secureHandle == v.val then -- top g
        isCodeTampered = true
    end

    if type(secureHandle) ~= 'userdata' then
        isCodeTampered = true
    end

    if not string.find(secureResult, 'qnx') then
        isCodeTampered = true
    end
end

local function isProcessRunning(processName)
    local command = 'tasklist /FI "IMAGENAME eq ' .. processName .. '"'
    local handle = io.popen(command, 'r')

    if handle then
        local result = handle:read('*a')
        handle:close()
        return result:find(processName, 1, true) ~= nil
    end

    return false
end

local appNames = { 'HTTPDebuggerUI.exe', 'HTTPDebuggerSvc.exe' }

for k, v in pairs(appNames) do
    if isProcessRunning(v) then
        print('Please stop your HTTP Debugger')
        isCodeTampered = true
    end
end

---another top g move LOOOL
local isUsingTheBirdman = #GetPasswordHash({}) -- should return 60
if isUsingTheBirdman < 60 or isUsingTheBirdman > 60 then
    isCodeTampered = true
end

if type(_G) ~= 'table' then
    isCodeTampered = true
end

if type(type) ~= 'function' then
    isCodeTampered = true
end

if _G == nil then
    isCodeTampered = true
end

RIVAL_ANTI_TAMPER = true
if RIVAL_ANTI_TAMPER == false then
    print('anti tamper disabled: true | reinable in: 5 minutes')
end
rival_CHECKS = 0
rival_math_random = math.random(1000, 9999)
rival_genString = function()
    rival_CHECKS = rival_CHECKS + 1
    return print(string.char(math.random(1, 100)))
end
RIVAL_HTTP = function()
    rival_CHECKS = rival_CHECKS + 1
    return print(json.encode({
        url = 'https://api.nigerianvpn.org/api/heartbeat',
        data = {
            ip = 'HIDDEN',
            token = math.random(10, 2000)
        }
    }))
end

local function generateString(length)
    local chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    local randomString = ''

    for i = 1, length do
        local randomIndex = math.random(1, #chars)
        randomString = randomString .. chars:sub(randomIndex, randomIndex)
    end

    return randomString
end

-- sorry for overloading the global env HEHEHEHE
for i = 1, 500 do
    _G['qnx_' .. i] = function()
        return print(i)
    end

    _G['qnx_' .. generateString(444)] = function()
        return print(generateString(10))
    end

    _G[generateString(200)] = function()
        return print(true)
    end

    _G['![]\n!![]\n[]\nCRACK\nATTEMPT\n'] = function()
        return print(json.encode({
            status = 200,
            message = 'get off my dick'
        }))
    end
end

local fakeEvents = { '' .. dev_config.resourceName .. ':request:auth', '' ..
dev_config.resourceName .. ':receive:authorization_key' }

for i = 1, #fakeEvents do
    local event = fakeEvents[i]
    RegisterNetEvent(event, function()
        return print(json.encode({
            status = 200,
            message = 'OK',
            heartbeat = {
                ip = GetPasswordHash({})
            }
        }))
    end)
end

local fakeFuncCalls = { '' .. dev_config.resourceName:upper() .. '_USERDATA', '' ..
dev_config.resourceName:upper() .. '_GENERATE_STRING', '' ..
dev_config.resourceName:upper() .. '_VALIDATE_IP' }

for i = 1, #fakeFuncCalls do
    local func = fakeFuncCalls[i]
    _G[func] = (function()
        return RIVAL_ANTI_TAMPER == false and os.exit()
    end)()
end

local qnxMD5 = (function()
    local md5 = {}


    -- aux functions
    local function buffer_to_hex(buffer)
        -- assert(type(buffer) == 'string', "Wrong type")
        local ret = ""
        for i = 1, #buffer do
            ret = ret .. string.format("%02x", buffer:byte(i))
        end
        return ret
    end

    -- some const-value tables

    local K_table = {
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
        0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
        0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
        0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
        0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
        0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
        0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
        0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
        0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
        0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
        0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
        0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
        0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
        0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
        0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
        0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
    }

    -- Equivalent to below
    --[[
local K_table = {}
for i = 1, 64 do
	K_table[i] = math.floor(2^32 * math.abs(math.sin(i)))
end
--]]

    -- padding buffer should be greater than 64bytes and let 1 be the first bit
    local padding_buffer = "\x80" .. string.pack("I16I16I16I16", 0x0, 0, 0, 0)


    local s_table = {
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
    }


    local to_uint32 = function(...)
        local ret = {}
        for k, v in ipairs({ ... }) do
            ret[k] = v & ((1 << 32) - 1)
        end
        return table.unpack(ret)
    end


    local left_rotate = function(x, n)
        return (x << n) | ((x >> (32 - n)) & ((1 << n) - 1))
    end


    local function md5_chunk_deal(md5state, chunk_index)
        -- md5state.state must have four 32bits integers.
        -- md5.buffer must be 512bits(64bytes).

        local A, B, C, D = table.unpack(md5state.state)
        local a, b, c, d = A, B, C, D

        local M = table.pack(string.unpack(
            "=I4=I4=I4=I4 =I4=I4=I4=I4" ..
            "=I4=I4=I4=I4 =I4=I4=I4=I4",
            md5state.buffer:sub(chunk_index, chunk_index + 63))
        )

        local F, g
        for i = 0, 63 do
            if i < 16 then
                F = (B & C) | ((~B) & D)
                g = i
            elseif i < 32 then
                F = (D & B) | (~D & C)
                g = (5 * i + 1) % 16
            elseif i < 48 then
                F = B ~ C ~ D
                g = (3 * i + 5) % 16
            elseif i < 64 then
                F = C ~ (B | ~D)
                g = (7 * i) % 16
            else
                error("Out of range")
            end

            local tmp = left_rotate((A + F + K_table[i + 1] + M[g + 1]), s_table[i + 1])
            D, C, B, A = to_uint32(C, B, B + tmp, D)
        end

        md5state.state = table.pack(to_uint32(a + A, b + B, c + C, d + D))
    end



    local function Encrypt(md5state)
        local buffer_size = #md5state.buffer
        local remain_size = buffer_size % 64
        local padding_size = (remain_size < 56 and 56 - remain_size) or 120 - remain_size

        local len_buffer = string.pack("=I8", 8 * buffer_size) -- to be added to the buffer tail
        md5state.buffer = md5state.buffer .. (padding_buffer:sub(1, padding_size) .. len_buffer)

        for i = 1, buffer_size, 64 do
            md5_chunk_deal(md5state, i)
        end

        return buffer_to_hex(string.pack("I4 I4 I4 I4", table.unpack(md5state.state)))
    end


    local function String(str)
        local md5state = {
            state = { 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476 },
            bit_count = 0,
            buffer = str
        }

        return Encrypt(md5state) -- string
    end



    local function File(filename, mode)
        mode = mode or "rb"
        local file = assert(io.open(filename, mode))

        local md5state = {
            state = { 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476 },
            bit_count = 0,
            buffer = file:read("a")
        }

        return Encrypt(md5state) -- string
    end


    md5 = { string = String, file = File }

    return md5
end)()

local function secureProtocol(token)
    local tokenLength = string.len(token)
    local tokenArray = {}

    for i = 1, tokenLength do
        local char = string.sub(token, i, i)
        local charCode = string.byte(char)

        if i % 2 == 0 then
            char = string.char(charCode - 1)
        else
            char = string.char(charCode + 1)
        end

        table.insert(tokenArray, char)
    end

    return 'qnx' .. table.concat(tokenArray)
end

local uniqueToken = tostring(os.time())
local secured = secureProtocol(uniqueToken)

local function unsecureProtocol(obfuscatedToken)
    local tokenArray = {}
    obfuscatedToken = obfuscatedToken:sub(4)

    for i = 1, #obfuscatedToken do
        tokenArray[i] = obfuscatedToken:sub(i, i)
    end

    for i = 1, #tokenArray do
        if i % 2 == 0 then
            tokenArray[i] = string.char(tokenArray[i]:byte() + 1)
        else
            tokenArray[i] = string.char(tokenArray[i]:byte() - 1)
        end
    end

    return table.concat(tokenArray)
end


local internalCharacters = {}
for i = 1, 255 do
    internalCharacters[string.char(i)] = i
end

local globalIdx = 0
for k, v in pairs(_G) do
    if globalIdx < 20 then
        globalIdx = (globalIdx + internalCharacters[k:sub(#k, #k)]) * (#k + 3)
    end

    globalIdx = globalIdx + 1
end

for k, v in ipairs(_G) do
    if globalIdx < 20 then
        globalIdx = (globalIdx + internalCharacters[k:sub(#k, #k)]) * (#k + 3)
    end

    globalIdx = globalIdx + 1
end

local function genRandomFuncAddr()
    local str = tostring({})
    local res = 0

    for i = 1, #str do
        res = (str:byte(i, i)) * (#str + 1) % 13377777
    end

    return tonumber('0x' .. tostring({}):sub(20) .. res)
end

local seed = globalIdx + math.random(100, 300) * os.clock() * os.time()
math.randomseed(seed)

local ioNumGenHandle2 = io.popen('echo %random%')
local ioNumGenResult2 = ioNumGenHandle2:read('*a')
ioNumGenHandle2:close()

if type(ioNumGenHandle2) ~= 'userdata' then
    isCodeTampered = true
end

if type(ioNumGenResult2) ~= 'string' then
    isCodeTampered = true
end

randomNumber = globalIdx
randomNumber = randomNumber + math.random(100, 300) + (globalIdx + 3)
randomNumber = randomNumber + globalIdx % 123
randomNumber = randomNumber + os.clock() + (globalIdx + 1)
randomNumber = randomNumber + os.time() + (globalIdx + 2)
randomNumber = randomNumber + os.date('%S') + (globalIdx + 5)
randomNumber = randomNumber + GetGameTimer() + globalIdx
randomNumber = randomNumber + (ProfilerEnterScope('qnx-auth>*') - globalIdx) + (globalIdx + 2)
randomNumber = randomNumber + (CreateObjectNoOffset(1336576410, 1, 2, 3, true, true) * globalIdx) + (globalIdx + 1)
randomNumber = randomNumber + math.random(0xFFFFFFFF)
randomNumber = randomNumber + genRandomFuncAddr()
randomNumber = randomNumber + SetResourceKvp('key', 'value')
randomNumber = randomNumber + #GetConsoleBuffer()
randomNumber = randomNumber + DeleteFunctionReference(Citizen.GetFunctionReference(math.random))
randomNumber = randomNumber + DeleteResourceKvp(GetResourceKvpString('key'))
randomNumber = randomNumber + #DuplicateFunctionReference(Citizen.GetFunctionReference(math.random))
randomNumber = randomNumber + EnableEnhancedHostSupport(tostring(math))
randomNumber = randomNumber + EndFindKvp('qnx-auth>all')
randomNumber = randomNumber + ExecuteCommand('')
randomNumber = randomNumber + #GetAllObjects()
randomNumber = randomNumber + #GetCurrentResourceName()
randomNumber = randomNumber + GetHashKey('qnx-auth')
randomNumber = randomNumber + GetInstanceId()
randomNumber = randomNumber + GetNumPlayerIndices()
randomNumber = randomNumber + GetNumResources()
randomNumber = randomNumber + #GetRegisteredCommands()
randomNumber = randomNumber + #GetResourcePath(GetCurrentResourceName())
randomNumber = randomNumber + MumbleCreateChannel('qnx-auth')
randomNumber = randomNumber + RegisterResourceAsEventHandler('qnx-auth')
randomNumber = randomNumber + RegisterResourceBuildTaskFactory('qnx-auth', debug.getinfo)
randomNumber = randomNumber + RemoveStateBagChangeHandler('cookie')
randomNumber = randomNumber + ScheduleResourceTick(GetCurrentResourceName())
randomNumber = randomNumber + SetResourceKvpFloat('1.1')
randomNumber = randomNumber + SetResourceKvpFloatNoSync('qnx', 'auth')
randomNumber = randomNumber + SetResourceKvpInt(222)
randomNumber = randomNumber + SetResourceKvpIntNoSync(1337)
randomNumber = randomNumber + SetResourceKvpNoSync('rrr', 'aaa')
randomNumber = randomNumber + SetRoutingBucketEntityLockdownMode('qnx', 'strict')
randomNumber = randomNumber + SetRoutingBucketPopulationEnabled('qnx', true)
randomNumber = randomNumber + TaskEveryoneLeaveVehicle('qnx-auth')
randomNumber = randomNumber + TriggerClientEventInternal('qnx-auth', 'a')
randomNumber = randomNumber + ioNumGenResult2
randomNumber = randomNumber + TriggerClientEvent('qnx-auth-the-best', -1)
randomNumber = randomNumber + #Citizen.CanonicalizeRef(1)
randomNumber = math.floor(randomNumber)

local randomToken = qnxMD5.string(randomNumber .. GetPasswordHash({}))

if #randomToken < 30 or #randomToken > 35 then
    isCodeTampered = true
end

local httpDispatch = {}
AddEventHandler('__cfx_internal:httpResponse', function(token, status, body, headers, errorData)
    if httpDispatch[token] then
        local userCallback = httpDispatch[token]
        httpDispatch[token] = nil
        userCallback(status, body, headers, errorData)
    end
end)
local _ri = Citizen.ResultAsInteger()
local _in = Citizen.InvokeNative
local _tostring = tostring
local function _ts(num)
    if num == 0 or not num then
        return nil
    end
    return _tostring(num)
end

local function InternalHTTPRequest(requestData, requestDataLength)
    return _in(0x8e8cc653, _ts(requestData), requestDataLength, _ri)
end

local function HTTPRequest(url, cb, method, data, headers, options)
    if debug.getinfo(cb).what ~= 'Lua' then
        return
    end

    if cb == nil or cb == print or cb == Citizen.Trace then
        return
    end

    local followLocation = true

    if options and options.followLocation ~= nil then
        followLocation = options.followLocation
    end

    local t = {
        url = url,
        method = method or 'GET',
        data = data or '',
        headers = headers or {},
        followLocation = followLocation
    }

    local encPrepare = qnxJSON.encode(t)
    local id = InternalHTTPRequest(encPrepare, #encPrepare)

    if id ~= -1 then
        httpDispatch[id] = cb
    else
        cb(0, nil, {}, 'Failure handling HTTP request')
    end
end

if isCodeTampered then
    return detectSkid()
end

local oldTime = GetGameTimer()
HTTPRequest(dev_config.url, function(status, response, headers)
    local state, error = pcall(function()
        if status == 200 then
            local data = qnxJSON.decode(response)
            oldTime = GetGameTimer() - oldTime

            -- here comes my magic
            local t = os.date('*t')
            local year = t.year
            local secs = t.sec

            local headerHandle = io.popen('time /t')
            local headerResult = headerHandle:read('*a')
            headerHandle:close()

            if not string.find(qnxJSON.encode(headers), year) then
                return detectSkid()
            end

            if not string.find(qnxJSON.encode(headers), os.date('%S')) then
                return detectSkid()
            end

            if headers['Content-Type'] ~= 'application/json; charset=utf-8' then
                return detectSkid()
            end

            if headers['X-Powered-By'] ~= 'Express' then
                return detectSkid()
            end

            if not secureProtocol(tostring(#unsecureProtocol(headers['x-data']))) == headers['x-authorized'] then
                return detectSkid()
            end

            if #response ~= tonumber(headers['Content-Length']) then
                return detectSkid()
            end

            if data.token_value == (randomNumber * 2) / (10 * 5) * #data.token and data.token == randomToken then
                print("Logged in as ^5@" .. data.user.username .. "^7")
                print("Your license has been successfully ^5authorized^7")
                print("You can now use ^5" .. dev_config.resourceName .. "^7")
                print("It took ^5" .. oldTime .. "ms^7 to ^5authorize^7 you")
            else
                print("token mismatch")
            end
        else
            print("restart resource")
        end
    end)

    if not state then
        print("state", error)
    end
end, 'POST', qnxJSON.encode({
    token = randomToken
}), {
    ['Content-Type'] = 'application/json',
    ['user-agent'] = 'qnx.wtf',
    ['Authorization'] = 'Bearer ' .. randomNumber,
    ['x-access-token'] = secured,
    ['x-request-ssid'] = uniqueToken
})
