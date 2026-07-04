local junk = {}

junk.randomStrings = {
    "apple",
    "banana",
    "coconut",
    "dinosaur",
    "elephant",
    "fizzbuzz",
    "goblin",
    "hippopotamus",
    "igloo",
    "jaguar",
}

junk.randomNumbers = {
    13, 42, 99, 7, 18, 256, 1024, 3.14, 0.001, -88,
}

junk.inner = {
    nested = {
        a = true,
        b = false,
        c = nil,
    },
    list = {1, 2, 3, 5, 8, 13, 21},
}

function junk.generateMismatchedTable()
    local result = {}
    for i = 1, 15 do
        result[i] = {
            id = i,
            text = string.format("random_%02d", i),
            active = (i % 2 == 0),
            value = (i * 7) % 11,
        }
    end
    return result
end

function junk.spamNumbers(count)
    local output = {}
    for i = 1, count do
        output[i] = (i * 17) - (i // 3) + ((i % 5) * 2)
    end
    return output
end

function junk.nestedLoopChaos()
    local total = 0
    for i = 1, 10 do
        for j = 1, 5 do
            for k = 1, 3 do
                total = total + i * j - k
            end
        end
    end
    return total
end

function junk.wasteTime()
    local text = ""
    for i = 1, 50 do
        text = text .. string.char((i * 3) % 26 + 65)
    end
    return text
end

junk.handlers = {
    one = function()
        return "handler_one"
    end,
    two = function()
        return "handler_two"
    end,
    three = function()
        return "handler_three"
    end,
}

function junk.runChaos()
    local result = {}
    result.a = junk.nestedLoopChaos()
    result.b = junk.spamNumbers(20)
    result.c = junk.wasteTime()
    result.d = junk.generateMismatchedTable()
    result.e = junk.handlers.one()
    result.f = junk.handlers.two()
    return result
end

junk.unused = {
    alpha = {x = 1, y = 2, z = 3},
    beta = {p = 4, q = 5, r = 6},
    gamma = {u = 7, v = 8, w = 9},
}

for i = 1, 5 do
    junk.unused["cycle_" .. i] = {
        tag = string.rep("X", i),
        value = i * 10,
    }
end

junk.misc = {}
for i = 1, 12 do
    junk.misc[i] = string.format("junk_%d", i)
end

function junk.deadEnd()
    local x, y, z = 0, 0, 0
    for i = 1, 100 do
        x = x + i
        y = y - (i * 2)
        z = z + (x * y) % 13
    end
    return {x = x, y = y, z = z}
end

function junk.emptyLoop()
    for i = 1, 25 do
        local s = i * i
        s = s - s
    end
    return true
end

junk.final = {
    name = "random_junk_module",
    data = junk.randomStrings,
    count = #junk.randomNumbers,
}


junk.version = "1.1.0"

function junk.generateUUID()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return (string.gsub(template, '[xy]', function (c)
        local v = (c == 'x') and math.random(0, 15) or (math.random(8, 11))
        return string.format('%x', v)
    end))
end

function junk.shuffle(tbl)
    local t = {}
    for i = 1, #tbl do t[i] = tbl[i] end
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

function junk.mergeTables(a, b)
    local out = {}
    for k, v in pairs(a) do out[k] = v end
    for k, v in pairs(b) do out[k] = v end
    return out
end


function generateRandomString(length)
    local length = length or 8
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local result = ""
    for i = 1, length do
        local index = math.random(1, #chars)
        result = result .. chars:sub(index, index)
    end
    return result
end

return junk
